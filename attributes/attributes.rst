Reflection on attributes
========================

There are numerous use cases for reflection on attributes and they do open possibilities that reflection on other entity do not.

Most importantly, it could be used as tags/filters to apply transformations to only specific entities. For example,
::

    [[qt::signal]] void f();
    void g();

Here, ``f()`` is a Qt signal, but since signals are regular functions, it make no sense to abuse the type-system
with something like ``QSignal<void> f();`` to be able to filter signals.

A prime use case for reflection is also serialization and data mapping.
Users may want to only serialize specific field. Here we map the member ``m_name`` to a json field ``name``

::

    struct Foo {
        [[json:json_value("name")]] std::string m_name;
        std::string m_buffer;
    };

Beyond filtering, reflecting on attributes combined with code-injection would also enable
features similar to python generators.

But, how can you extract attributes parameters ?
**I propose that user-defined attributes can be declared before use.**

Placeholder syntax:
::

   namespace json {
       using json_value_attribute = [[json_value(const char*)]];
   }

This declares an attribute ``json:json_value`` taking a single parameter as a ``const char*``.

From this declaration, the compiler would generate a structure that could look like
::

    struct json_value_attribute {
        json_value_attribute() = delete;
        static auto name();  // returns "json_value"
        auto get_args_count() const; // returns 1;
        template<int N, std::enable_if_t<N == 0, int> = 0>
        const char* arg() const;
    };

Where:
 - ``name()`` is the name of the attribute
 - ``args_count()`` returns the number of attributes. This can varies at each instantiation because attributes support variadic parameters
 - ``arg<N>`` returns the parameter at position ``N``

Attributes can have a variadic number of parameters, for example ``[[foo(double, int...)]]``.
From this attribute, the compiler can generate the following structure.
::

    struct foo_attribute {
        foo_attribute() = delete;
        auto get_args_count() const;
        template<int N, std::enable_if_t<N == 0, int> = 0>
        double arg() const;
        template<int N, std::enable_if_t<N >= 1, int> = 0>
        int arg() const;
    };

Because the number of parameters may vary from instance to instance, we can not make use of a tuple-like object.



From there, querying attributes would be rather straight forward.


For example, to iterate over the serializable field of a struct/class (using syntax from P0953R0)
::

    constexpr for(RecordMember const * member : meta->get_public_data_members()) {
        constexpr for(reflect::Attribute const* attribute : member->get_attributes()) {
            if(std::is_same_v<unreflexpr(attribute), json::json_value_attribute>) {
                json[attribute->args().get<0>()] = to_json(....);
            }
        }
    }

There are a few benefits to this approach:

Forcing attributes to be declared can let the compiler provide better diagnostics when a typo is made.
::

    [[json:jsonvalue("name")]]  //Warning, did you mean json_value ?

It also enforces that the proper number and type of parameters are given.
For example, ``[[deprecated()]]`` requires that its optional parameter be a string, which is currently handled on a case by case basis by the compiler.

Similarly, when querying for attributes, there is no need to fiddle with strings,
this can it can lead to better tooling (attribute completion) and make it impossible to reflect on attributes that do not exist.
::

    // typo, but how can the compiler possibly know that ?
    member->has_attribute("json_vale");

It also unify the type system namespaces with the attributes namespaces, which would be hard to reconcile otherwise.



The type of attributes parameters is not enforced at the language level, so the language accept mixed-type attributes value.
::

    [[foo(0)]] void f();
    [[foo("bar")]] void g();

I do not offer a mechanism to support this use case. However, it could be solved by the use of a ``constexpr`` variant-like type:
::

    namespace foo {
        using foo_attribute = [[foo(std::static_variant<int, const char*>)]];
    }

I do believe this is out of scope of the reflection proposal, even if it would be worth exploring.

In the same fashion, we could support optional parameters by using a ``constexpr`` ``std::optional`` like type,
and/or supporting default values for attributes
::

    namespace foo {
        using foo_attribute = [[foo(int, int = 0)]];
    }


Compatibility with toolings and undeclared attributes:
------------------------------------------------------

Some attributes are used only by external tools and should therefore not required to be declared before being used.
However that begs the question of how compilers should handle attributes they do not know about.
Requiring a declaration would be a breaking change so it is not possible.

Obviously, only attributes that are declared can be reflected upon.


Compatibility with standard attributes:
---------------------------------------

Attributes that we want to expose to reflection could be declared in the namespace std. We may need to have a special handling so that
standard attributes can be declared in the namespace std while not being in any namespace.

User-defined attributes must be in a namespace. This is to avoid name collision with future standard attributes.
It is therefore invalid to declare attributes in the global namespace.

Compatibility with contracts
----------------------------

Contracts-related attributes are not declared (and therefore) reflect-able upon both because it would make little sense and their format is not
identical to other attribute
