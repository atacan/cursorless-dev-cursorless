;; https://github.com/tree-sitter/tree-sitter-go/blob/master/src/grammar.json

;; @statement generated by the following command:
;;  curl https://raw.githubusercontent.com/tree-sitter/tree-sitter-go/master/src/node-types.json | jq '[.[] | select(.type == "_statement" or .type == "_simple_statement") | .subtypes[].type]' | grep -v '\"_' | sed -n '1d;p' | sed '$d' | sort
;; and then cleaned up.
[
  (assignment_statement)
  ;; omit block for now, as it is not clear that it matches Cursorless user expectations
  ;; (block)
  (break_statement)
  (const_declaration)
  (continue_statement)
  (dec_statement)
  (defer_statement)
  (empty_statement)
  (expression_statement)
  (expression_switch_statement)
  (fallthrough_statement)
  (for_statement)
  (go_statement)
  (goto_statement)
  (if_statement)
  (inc_statement)
  (labeled_statement)
  (return_statement)
  (select_statement)
  (send_statement)
  (short_var_declaration)
  (type_declaration)
  (type_switch_statement)
  (var_declaration)
] @statement

(
  (interpreted_string_literal) @string @textFragment
  (#child-range! @textFragment 0 -1 true true)
)

(
  (raw_string_literal) @string @textFragment
  (#character-range! @textFragment 1 -1)
)

(comment) @comment @textFragment

;; What should map and list refer to in Go programs?
;;
;; The obvious answer is that map should refer to map and struct composite literals,
;; and that list should refer to slice and array composite literals.
;;
;; There are two problems with this answer.
;;
;;   * The type of a composite literal is a semantic, not a syntactic property of a program.
;;       - What is the type of T{1: 2}? It could be array, map, or slice.
;;       - What about T{a: 1}? It could be map or struct.
;;       - What about T{1, 2}? It could be struct, array, or slice.
;;     Cursorless only has syntactic information available to it.
;;
;;   * The user might not know the type either. With a named type, the type definition might be far away.
;;     Or it might just be offscreen. Either way, the user needs to be able to make a decision about
;;     what scope to use using only locally available, syntactic information.
;;     Note that this also means that has-a predicates work better than has-no predicates.
;;     The user can locally confirm that there is a keyed element.
;;     She cannot confirm locally that there is no keyed element; it might just not be visible.
;;
;; Combining all these constraints suggests the following simple rules:
;;
;;   * If there is a keyed element present, then it is a map.
;;   * If there is a non-keyed element present, then it is a list.
;;   * If there are both or neither, then it is both a map and a list.
;;
;; Conveniently, this is also simple to implement.
;;
;; This guarantees that a user always knows how to refer to any composite literal.
;; There are cases in which being overgenerous in matching is not ideal,
;; but they are rarer, so let's optimize for the common case.
;; Mixed keyed and non-keyed elements are also rare in practice.
;; The main ambiguity is with {}, but there's little we can do about that.
;;
;; Go users also expect that the map and list scopes will include the type definition,
;; as well as any & before the type. (Strictly speaking it is not part of the literal,
;; but that's not how most humans think about it.)
;;
;; If you are considering changing the map and list scopes, take a look at the examples in
;; data/playground/go/maps_and_lists.go, which cover a fairly wide variety of cases.

;; maps

;; &T{a: 1}
(unary_expression
  operator: "&"
  (composite_literal
    body: (literal_value
      (keyed_element)
    )
  )
) @map

;; T{a: 1}
(
  (composite_literal
    body: (literal_value
      (keyed_element)
    )
  ) @map
  (#not-parent-type? @map unary_expression)
)

;; {a: 1}
(
  (literal_value
    (keyed_element)
  ) @map
  (#not-parent-type? @map composite_literal)
)

;; lists

;; &T{1}
(unary_expression
  operator: "&"
  (composite_literal
    body: (literal_value
      (literal_element)
    )
  )
) @list

;; T{1}
(
  (composite_literal
    body: (literal_value
      (literal_element)
    )
  ) @list
  (#not-parent-type? @list unary_expression)
)

;; {1}
(
  (literal_value
    (literal_element)
  ) @list
  (#not-parent-type? @list composite_literal)
)

;; empty composite literals

;; &T{}
(unary_expression
  operator: "&"
  (composite_literal
    body: (literal_value
      .
      "{"
      .
      (comment)*
      .
      "}"
      .
    )
  )
) @list @map

;; T{}
(
  (composite_literal
    body: (literal_value
      .
      "{"
      .
      (comment)*
      .
      "}"
      .
    )
  ) @list @map
  (#not-parent-type? @list unary_expression)
)

;; {}
(
  (literal_value
    .
    "{"
    .
    (comment)*
    .
    "}"
    .
  ) @list @map
  (#not-parent-type? @list composite_literal)
)

;; Functions

;; function declaration, generic function declaration, function stub
;; func foo() {}
;; func foo[]() {}
;; func foo()
(function_declaration
  name: (_) @functionName
  body: (block
    .
    "{" @interior.start.endOf
    "}" @interior.end.startOf
    .
  )?
) @namedFunction @functionName.domain @interior.domain

;; method declaration
;; func (X) foo() {}
(method_declaration
  name: (_) @functionName
  body: (block
    .
    "{" @interior.start.endOf
    "}" @interior.end.startOf
    .
  )
) @namedFunction @functionName.domain @interior.domain

;; func literal
(func_literal
  body: (block
    .
    "{" @interior.start.endOf
    "}" @interior.end.startOf
    .
  )
) @anonymousFunction @namedFunction @interior.domain

;; switch-based branch

(
  [
    (default_case)
    (expression_case)
    (type_case)
  ] @branch
  (#trim-end! @branch)
  (#insertion-delimiter! @branch "\n")
)

[
  (type_switch_statement)
  (expression_switch_statement)
] @branch.iteration

;; if-else-based branch

;; first if in an if-else chain
(
  (if_statement
    consequence: (block) @branch.end.endOf
  ) @branch.start.startOf
  (#not-parent-type? @branch.start.startOf if_statement)
  (#insertion-delimiter! @branch.start.startOf " ")
)

;; internal if in an if-else chain
(if_statement
  "else" @branch.start
  alternative: (if_statement
    consequence: (block) @branch.end
  )
  (#insertion-delimiter! @branch.start " ")
)

;; final else branch in an if-else chain
(
  (if_statement
    "else" @branch.start.startOf
    alternative: (block)
  ) @branch.end.endOf
  (#insertion-delimiter! @branch.start.startOf " ")
)

;; iteration scope is always the outermost if statement
(
  (if_statement) @branch.iteration
  (#not-parent-type? @branch.iteration if_statement)
)

(if_statement) @ifStatement

[
  (call_expression)
  (composite_literal)
] @functionCall

(call_expression
  function: (_) @functionCallee
) @_.domain
(composite_literal
  type: (_) @functionCallee
) @_.domain

(keyed_element
  .
  (_) @collectionKey
  .
  (_) @value
) @_.domain

(return_statement
  (expression_list) @value
) @_.domain

(literal_value) @collectionKey.iteration @value.iteration

[
  (pointer_type)
  (qualified_type)
  (type_identifier)
] @type

(function_declaration
  result: (_) @type
) @_.domain
(method_declaration
  result: (_) @type
) @_.domain

;;!! if true {}
(
  (_
    condition: (_) @condition
  ) @_.domain
  (#not-type? @condition parenthesized_expression)
)

;;!! if (true) {}
(
  (_
    condition: (parenthesized_expression) @condition
  ) @_.domain
  (#child-range! @condition 0 -1 true true)
)

;;!! func add(x int, y int) int {}
(
  (parameter_list
    (_)? @_.leading.endOf
    .
    (_) @argumentOrParameter
    .
    (_)? @_.trailing.startOf
  ) @_dummy
  (#not-type? @argumentOrParameter "comment")
  (#single-or-multi-line-delimiter! @argumentOrParameter @_dummy ", " ",\n")
)

;;!! add(1, 2)
(
  (argument_list
    (_)? @_.leading.endOf
    .
    (_) @argumentOrParameter
    .
    (_)? @_.trailing.startOf
  ) @_dummy
  (#not-type? @argumentOrParameter "comment")
  (#single-or-multi-line-delimiter! @argumentOrParameter @_dummy ", " ",\n")
)

(parameter_list
  "(" @argumentOrParameter.iteration.start.endOf
  ")" @argumentOrParameter.iteration.end.startOf
) @argumentOrParameter.iteration.domain
(argument_list
  "(" @argumentOrParameter.iteration.start.endOf
  ")" @argumentOrParameter.iteration.end.startOf
) @argumentOrParameter.iteration.domain

operator: [
  "<-"
  "<"
  "<<"
  "<<="
  "<="
  ">"
  ">="
  ">>"
  ">>="
] @disqualifyDelimiter
(send_statement
  "<-" @disqualifyDelimiter
)
