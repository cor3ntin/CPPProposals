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
on a generous interpretation of [temp.inst]/9

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

## [over.match.funcs.general] Candidate functions and argument lists {-}

> [7]{.pnum} In each case where conversion functions of a class `S` are considered for initializing an object or reference of type `T`, the candidate functions include the result of a search for the _conversion-function-id_ `operator T` in `S`. [Any specialization of a conversion function template found by this search is potentially generated ([temp.over]).]{.add} [. . .]
>
> [8]{.pnum} In each case where a candidate is a function template, candidate function template specializations are [potentially]{.add} generated using template argument deduction ([temp.over], [temp.deduct]). If a constructor template or conversion function template has an _explicit-specifier_ whose _constant-expression_ is value-dependent ([temp.dep]), template argument deduction is performed first and then, if the context admits only candidates that are not explicit and the generated specialization is explicit ([dcl.fct.spec]), it will be removed from the candidate set. Those candidates are then handled as candidate functions in the usual way.^93^ A given name can refer to, or a conversion can consider, one or more function templates as well as a set of non-template functions. In such a case, the candidate functions generated from each function template are combined with the set of non-template candidate functions.

## [over.match.best.general] Best viable function {-}

> [1]{.pnum} Define ICS^*i*^(`F`) as the implicit conversion sequence that converts the *i*^th^ argument in the list to the type of the *i*^th^ parameter of viable function `F`. [over.best.ics] defines the implicit conversion sequences and [over.ics.rank] defines what it means for one implicit conversion sequence to be a better conversion sequence or worse conversion sequence than another.
>
> [2]{.pnum} Given these definitions, a viable function `F`~1~ is defined to be a _better_ function than another viable function `F`~2~ if for all arguments *i*, ICS^*i*^(`F`~1~) is not a worse conversion sequence than ICS^*i*^(`F`~2~), and then
>
>  - [. . .]
>
> ::: add
>
> [2a]{.pnum} A viable function *F* is a _perfect viable function_ if
>
>  - [(2a.1)]{.pnum} *F* is not a function template specialization,
>  - [(2a.2)]{.pnum} for all arguments *i*, ICS^*i*^(*F*) is a perfect conversion sequence ([over.ics.scs]), and
>  - [(2a.3)]{.pnum} if *F* is a conversion function, the implicit conversion sequence from the return type of *F* to the type of the object being initialized ([over.match.conv]) is a perfect conversion sequence.
>
> [2b]{.pnum} Let *S* be the set of viable functions among the candidates that are not function templates. If
>
>  - [(2b.1)]{.pnum} there is exactly one perfect viable function *F* in *S* that is better than all other viable functions in *S*,
>  - [(2b.2)]{.pnum} the overload resolution is not performed for a copy-initialization ([over.match.copy]), and
>  - [(2b.3)]{.pnum} either *F* is not a conversion function or no candidate is a constructor template,
>
> then *F* is the one selected by overload resolution.
>
> Otherwise, the potentially generated candidate function template specializations ([temp.over]) are generated and added to the set of viable functions if they are viable ([over.match.viable]).
>
> :::
>
> [3]{.pnum} If there is exactly one viable function that is a better function than all other viable functions, then it is the one selected by overload resolution; otherwise the call is ill-formed.^99^
>
> ::: example
> [. . .]
> :::
>
> [4]{.pnum}
>
> ::: note
> If the best viable function was made viable by one or more default arguments, additional requirements apply ([over.match.viable]).
> :::

## [over.ics.scs] Standard conversion sequences {-}

> [3]{.pnum} Each conversion in Table 19 also has an associated rank (Exact Match, Promotion, or Conversion). These are used to rank standard conversion sequences. The rank of a conversion sequence is determined by considering the rank of each conversion in the sequence and the rank of any reference binding. If any of those has Conversion rank, the sequence has Conversion rank; otherwise, if any of those has Promotion rank, the sequence has Promotion rank; otherwise, the sequence has Exact Match rank.
>
> [. . .]
>
> ::: add
>
> [4]{.pnum} A standard conversion sequence *S* is a _perfect conversion sequence_ if
>
>  - [(4.1)]{.pnum} the argument expression is not the _initializer-clause_ of a _braced-init-list_ with a single _initializer-clause_,
>  - [(4.2)]{.pnum} *S* consists of the identity conversion or an lvalue transformation, and
>  - [(4.3)]{.pnum} if the parameter has type “reference to *cv* *T*” and binds directly to the argument expression, the argument expression has type *cv* *T*.
>
> :::

## [over.over] Address of an overload set {-}

> [2]{.pnum} If there is no target, all non-template functions named are selected. Otherwise, a non-template function with type `F` is selected for the function type `FT` of the target type if `F` (after possibly applying the function pointer conversion ([conv.fctptr])) is identical to `FT`. [. . .]
>
> [3]{.pnum} The specialization, if any, [potentially]{.add} generated by template argument deduction ([temp.over], [temp.deduct.funcaddr], [temp.arg.explicit]) for each function template named is added to the set of selected functions considered.

## [temp.over] Overload resolution {-}

> [1]{.pnum} When a call of a function or function template is written (explicitly, or implicitly using the operator notation), [a function template specialization is _potentially generated_ from each function template. For each function template whose potentially generated specialization is required to determine the result of overload resolution ([over.match.best.general], [over.over]),]{.add} template argument deduction ([temp.deduct]) and checking of any explicit template arguments ([temp.arg]) are performed [for each function template]{.rm} to find the template argument values (if any) that can be used with that function template to instantiate a function template specialization that can be invoked with the call arguments or, for conversion function templates, that can convert to the required type.
>
> For each [such]{.add} function template:
>
>  - [(1.1)]{.pnum} If the argument deduction and checking succeeds, the *template-argument*s (deduced and/or explicit) are used to synthesize the declaration of a single function template specialization which is added to the candidate functions set to be used in overload resolution.
>  - [(1.2)]{.pnum} If the argument deduction fails or the synthesized function template specialization would be ill-formed, no such function is added to the set of candidate functions for that template.
>
> The complete set of candidate functions includes all the synthesized declarations and all of the non-template functions found by name lookup. The synthesized declarations are treated like any other functions in the remainder of overload resolution, except as explicitly noted in [over.match.best].^114^

# Acknowledgments

Thanks to people who contributed to the various discussions on this topic
on the Core reflector, and the LLVM and GCC bug trackers.
