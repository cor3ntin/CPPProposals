---
title: "On Overload Resolution, Exact Matches, and Clever Implementations"
document: P3606R1
date: 2025-01-24
audience:
 - Evolution Working Group
author:
 - name: Corentin Jabot
   email: <corentin.jabot@gmail.com>
 - name: Younan Zhang
   email: <zyn7109@gmail.com>
toc: false
---

# Revisions

## P3606R1

 - Provides wording

# Introduction

During overload resolution, if GCC finds an
exact non-ambiguous, non-template match,
it will pick that overload and will not perform
template argument deduction.

```cpp

template<typename T>
decltype([] { return T::x;}) f(T); // #1
void f(int) {} // #2

int main() {
  f(0);
}
```

In this example, GCC will pick `#2` (that is an exact match for all arguments) when calling `f(0)`.
GCC will not perform template argument deduction for `#1`.

In other implementations, this is ill-formed.

Indeed, in other implementations, `#1` will be instantiated before overload resolution
is performed, and `T::x` results in a substitution failure in
a non-immediate context (body of a lambda), which is a hard error.

The conformity of GCC's behavior hinges
on a generous interpretation of [temp.inst]{.sref}/9

> "If the function selected by overload resolution can be determined without instantiating a class template definition,
> it is unspecified whether that instantiation actually takes place."

Note that the [CWG consensus](https://lists.isocpp.org/core/2023/03/14042.php)
is that GCC's behavior is probably valid by the spirit of the law but not its letter.
In any case, CWG generally considers whether to mandate the GCC's behavior as an evolutionary matter.

Is it? After all, EWG might not care about whether diagnostics are produced in non-immediate contexts
during overload resolution. Let's make things more riveting with concepts. Consider

```cpp
struct S {
  template <typename T>
  requires std::copyable<T>
  explicit S(T op) noexcept; // #1
  S(const S&) noexcept = default; // #2
};
static_assert(std::copyable<S>);
```

This snippet is a reduction of code that is regularly submitted as an issue to implementations.

To check whether S satisfies `copyable`, we need to check that `S(declval<const S&>())` is a valid expression.
To that end, we perform overload resolution between `#1` and `#2` after instantiating `#2` with [T=S].
`#1` is constrained by `copyable`.

To understand whether S satisfies `copyable`, one must first understand whether S satisfies `copyable`.
The constraint depends on itself, and the program is ill-formed.

The user presumably wanted to write

```cpp
template <typename T>
requires (!std::same_as<T, S> && std::copyable<T>)
explicit S(T op) noexcept;
```

But why didn't they? Probably because GCC is perfectly happy with this program.
Indeed, When GCC performs overload resolution `#2` is a perfect match,
`#1` is never instantiated, and its constraints are never checked.

Concept checking, in particular for concepts that could lead to recursion make
GCC's optimization very much visible even without considering
errors in non-immediate contexts.

Because of that, we think the standard needs to clarify what are the allowed
implementation strategies. But this has been the status quo for years.
Why write this paper now?

## CWG2369 makes the status quo more observable.

Clang tried to implement the very useful [@CWG2369].
However, this unearthed the opposite issue. Consider

```cpp
template <typename U>
struct B { static_assert(false); };

template <typename T>
requires (sizeof(B<T>) == 1)
void f(T, typename T::foo = 0) {} // #1
void f(int) {} // #2

f(0);
```

Again, this code is reduced from actual bug reports. In particular, variation of that code
have been found in the standard library specification, libc++, and MSSTL ([@LWG4139]).

All compilers compile that code at the time of writing.
As usual, GCC will pick `#2` because it's an exact match, and `#1` is, therefore, never instantiated.

Clang, however, will try to instantiate `#1`. Because [@CWG2369] is not implemented in Clang,
we will substitute into the argument `T::foo` **before** evaluating the constraint.
Because `int::foo` is not a valid type, `#1` SFINAE-away, and we pick `#2`.

Therefore, existing code happens to be valid for both GCC and Clang for different reasons,
and that makes it difficult for Clang to deploy [@CWG2369], even if that would be a very useful
defect report to implement.

This brings us to this paper.

# Should the standard adopt GCC's behavior?

Adopting GCC's behavior, i.e., not considering template overload candidates when a non-template candidate
is an exact match (i.e., there is an exact match for every argument) would have some benefits:

 * The compiler has less work to do during overload resolution, improving compile times
 * It would make the adoption of [@CWG2369] less disruptive.
 * It would save users who forget a `same_as` constraint on templated constructors.
   This pattern/mistake is fairly common
   (but then again, this only happens because an implementation is more lenient than others).

The downside is that errors in the non-immediate context of template candidates would no longer be diagnosed.
A small price to pay?

On the other hand, if we do not want to bless GCC's behavior,
it's unclear how implementations would be able to deploy
CWG2369 as a DR, and should we expect GCC to change its implementation? That would break a non-trivial amount of code.

# Addendum: CWG2369 and recursive constraint checks.

Consider the following example [from GCC's bug tracker](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=99599):

```cpp
struct foo_tag{};
struct bar_tag{};

template <class T>
concept fooable = requires(T it) {
    invoke_tag(foo_tag{}, it);
};

template<class T>
T invoke_tag(foo_tag, T in); // #1

template<fooable T>
T invoke_tag(bar_tag, T it); // #2

int main() {
 // Neither line below compiles in GCC 11, independently of the other
    return invoke_tag(foo_tag{}, 2);
    return invoke_tag(bar_tag{}, 2);
}
```

In that scenario, both `invoke_tag` overloads are templates, so all implementations
instantiate both overloads.
After CWG2369, `fooable<T>` is checked for both overloads before looking at the validity of function
arguments; that will cause the constraints of `#2` to be rechecked during satisfaction.
`fooable<T>` always depends on itself and the program is ill-formed.

So GCC found that CWG2369 broke existing code (the above is a reduction from `tag_invoke`).
To remediate this, they changed the order of template argument deduction
to look at the arguments for which deduction would never produce an instantiation before considering constraints.

Doing so, in the example above, when checking the satisfaction of `fooable<T>`,
GCC realizes `#2` is not a valid overload for `invoke_tag(foo_tag{}, it)`, and pick `#1`,
which is not constrained, and therefore, there is no recursive checking, and both calls become valid.

No CWG issue was created for that, and it's unclear if it is EWG territory,
but it is worth mentioning as GCC employed a similar strategy than they do for overload resolution
to work around the breakages caused by CWG2369.

# Proposal Summary

During overload resolution, if there is a viable non-template candidate for which
every argument's conversion is an exact match, then template candidate are not
considered and argument deduction/substitution does not happen.

# Implementation experience

All strategies described here were implemented by at least one implementation,
which is exactly the issue!

Our main objective with this paper is to clarify intent so that we can
facilitate the implementation of CWG2369 (and [@CWG2769]) in Clang.

# Wording

## [over.match]{.sref} Overload resolution {-}

### [over.match.funcs.general]{.sref} Candidate functions and argument lists {-}

[Replace [over.match.funcs.general]/p8 as follow]{.ednote}

::: rm

[8]{.pnum}In each case where a candidate is a function template, candidate function template specializations are generated using template argument deduction ([temp.over], [temp.deduct]). If a constructor template or conversion function template has an explicit-specifier whose constant-expression is value-dependent ([temp.dep]), template argument deduction is performed first and then, if the context admits only candidates that are not explicit and the generated specialization is explicit ([dcl.fct.spec]), it will be removed from the candidate set. Those candidates are then handled as candidate functions in the usual way. A given name can refer to, or a conversion can consider, one or more function templates as well as a set of non-template functions. In such a case, the candidate functions generated from each function template are combined with the set of non-template candidate functions.

:::

::: add

[8]{.pnum} In each case where a candidate is a function template, it is added to the set of _prospective function template candidates_.
A given name can refer to, or a conversion can consider, one or more function templates as well as a set of non-template functions.
In such a case, if no perfect viable function is selected, candidate functions will be generated from each function template and will be added to the set of non-template candidate functions when the best function is selected [over.match.best].

[Note: If a perfect viable function is selected, candidate function templates are not considered and template argument deduction for these candidates does not take place.]

:::


[Add a new section after [over.match.viable]{.sref} ]{.ednote}

::: add

### [over.match.perfect] Perfect Viable Function {-}

A _perfect viable function_ is a function that has a perfect standard conversion
sequence  ([over.ics.scs]) for each of its arguments, and if it is a conversion function,
the conversion sequence to type of the object being initialized [over.match.conv]{.sref}
is a perfect standard conversion sequence.

:::

### [over.match.best.general]{.sref} General {-}

[Modify p3 as follow]{.ednote}

::: add

[3]{.pnum}  Except when performing overload resolution for copy initialization [over.match.copy], if

 - there is exactly one viable function `F` that is a better function than all other viable functions,
 - `F` is a perfect viable function, and
 - `F` is not a conversion function or the set of prospective function templates does not contain any constructor template,

then F is the one selected by overload resolution;


Otherwise, candidate function template specializations are generated from the set of prospective function template candidates using template argument deduction ([temp.over], [temp.deduct]).
If a constructor template or conversion function template has an explicit-specifier whose constant-expression is value-dependent ([temp.dep]), template argument deduction is performed first and then, if the context admits only candidates that are not explicit and the generated specialization is explicit ([dcl.fct.spec]), it will be removed from the candidate set. So generated candidate function template specializations are then added to the set of viable funtions if they are viable per [over.match.viable]. Those candidates are then handled as candidate functions in the usual way.

:::

[If]{.rm} [After the viable candidate function template specializations are added to the set of viable functions, if]{.add} there is exactly one viable function that is a better function than all other viable functions, then it is the one selected by overload resolution; otherwise the call is ill-formed.

### [over.ics.scs]{.sref} Standard conversion sequences {-}

[Add the following paragraph at the end of [over.ics.scs], after the table]{.ednote}

::: add

[4]{.pnum} A standard conversion sequence is a _perfect standard conversion sequence_ if

 - the argument expression is not the element of a single-element _braced-init-list_,
 - each conversion in the sequence, ignoring any initial lvalue transformation, is the identity conversion, and
 - if the conversion is a direct reference binding, the type of the argument expression and the type of the parameter are the same.

:::

# Acknowledgments

Thanks to people who contributed to the various discussions on this topic
on the Core reflector, and the LLVM and GCC bug trackers.
