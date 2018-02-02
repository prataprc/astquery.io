---
layout: home
---

ASTQuery is the simple idea of applying CSS selectors on
[Abstract Syntax Tree][ast-link].

Abstract Syntax Tree (AST) is constructed by parsing i/p text stream for
tokens and organizing tokens as a tree of Terminal nodes and NonTerminal nodes.
Typically, Terminal nodes are leaf nodes holding a token of symbols from
input stream. And NonTerminals are intermediate nodes that are constructed
using other intermediate and leaf nodes.

After parsing input text into AST, tree processing and/or transformation
algorithms are applied. There are two popular techniques used to parse
symbols of text and convert them to AST, one is using
[LALR][lalr-link] technique and the other is using
[Parser Combinator][parser-combinator-link]. For our case we are going to
use parser-combinator technique, more specifically we will be using a
golang implementation of parser combinator, [goparsec][goparsec-link].

## Composing a parser using goparsec

Below code is in [go-language](http://golang.org) with which goparsec is
authored. We shall compose a parser using goparsec to parse a well formed
HTML text, if you are keen to understand how the parser is composed please
refer to its [godoc-site][goparsec-godoc-link]. Going forward it is enough
to assume that `makehtmly` constructs and returns a HTML parser function
that can be used to parse a well formed HTML text.

```go
func makehtmly(ast *AST) Parser {
  var tag Parser

  // terminal parsers.
  tagobrk := Atom("<", "OT")
  tagcbrk := Atom(">", "CT")
  tagcend := Atom("/>", "CT")
  tagcopen := Atom("</", "CT")
  equal := Atom(`=`, "EQ")
  single := Atom("'", "SQUOTE")
  double := Atom(`"`, "DQUOTE")
  tagname := Token(`[a-zA-Z0-9]+`, "TAGNAME")
  attrname := Token(`[a-zA-Z0-9_-]+`, "ATTRNAME")
  attrval1 := Token(`[^\s"'=<>`+"`]+", "ATTRVAL1")
  attrval2 := Token(`[^']*`, "ATTRVAL2")
  attrval3 := Token(`[^"]*`, "ATTRVAL3")
  entity := Token(`&#?[a-bA-Z0-9]+;`, "ENTITY")
  text := Token(`[^<]+`, "TEXT")
  doctype := Token(`<!doctype[^>]+>`, "DOCTYPE")

  // parse tag attributes
  attrunquoted := ast.And(
      "attrunquoted", nil, attrname, equal, attrval1,
  )
  attrsingleq := ast.And(
      "attrsingleq", nil, attrname, equal, single, attrval2, single,
  )
  attrdoubleq := ast.And(
      "attrdoubleq", nil, attrname, equal, double, attrval3, double,
  )
  attr := ast.OrdChoice(
      "attribute", nil, attrsingleq, attrdoubleq, attrunquoted, attrname,
  )
  attrs := ast.Kleene("attributes", nil, attr, nil)

  // parse tags
  tagopen := ast.And("tagopen", nil, tagobrk, tagname, attrs, tagcbrk)
  tagclose := ast.And("tagclose", nil, tagcopen, tagname, tagcbrk)

  // parse tags and text
  content := ast.OrdChoice("content", nil, entity, text, &tag)
  contents := ast.Maybe(
      "maybecontents", nil, ast.Kleene("contents", nil, content, nil),
  )

  // parse HTML text
  tagempty := ast.And("tagempty", nil, tagobrk, tagname, attrs, tagcend)
  tagproper := ast.And("tagproper", nil, tagopen, contents, tagclose)
  tag = ast.OrdChoice("tag", nil, doctype, tagempty, tagproper)
  return ast.Kleene("html", nil, tag, nil)
}
```

With above parser let us try to parse as simple html text:

```html
<html>
    <body> <h1>My First Heading</h1> <p>My first paragraph.</p> </body>
</html>
```

Following code, again authored in go-language, parses `data` that contain
the html text using the `ast-object`. After the call to `Parsewith()`,
ast-object will hold on to the root node of the parse tree. We can use the
Dotstring() method to generate a graph-visualization for the entire parse
tree. Note that in the constructed parser we use goparsec's Terminal
and NonTerminal types for leaf nodes and intermediate nodes.

```go
  ast := NewAST("html", 100)
  y := makehtmly(ast)
  s := NewScanner(data).TrackLineno()
  ast.Parsewith(y, s)
  graph := ast.Dotstring("simplehtml")
```

Parse tree constructed using our parser for the example html text is rendered
below. This tree is called Abstract Syntax Tree.

![dotgraph](media/simplehtml.svg)

Nodes and attributes
--------------------

Now that we have got an example Abstract Syntax Tree to play with, let us turn
our attention to nodes within the Abstract Syntax Tree and explore what it
is made of.

In general, irrespective of the language used to parse the text, AST should
be made of NonTerminal nodes (intermediate nodes) and Terminal nodes (leaf
nodes). Nodes can either be a Terminal node or a NonTerminal node, also called
as leaf-node or intermediate-node. Typically, leaf-nodes are parsed by
tokenizers and intermediate-nodes are parsed by combinators. In the
Lex-and-Yacc parlance, we can say that leaf-nodes are parsed by lexers
and intermediate-nodes are parsed by yaccer.

First step in AST Query is to enable algorithms to walk through the tree,
and, subsequently algorithms should be able to query each node for matchable
selectors. To facilitate this, let us attach some behaviors to Terminal and
NonTerminal nodes and call the collection of behaviors as `Queryable`

```go
// Queryable interface to be implemented by all nodes, both terminal
// and non-terminal nodes within Abstract Syntax Tree.
type Queryable interface {
	// GetValue return parsed text, if node is NonTerminal it will
	// concat the entire sub-tree for parsed text and return the same.
	GetValue() string

	// GetChildren relevant only for NonTerminal node.
	GetChildren() []Queryable

	// SetAttribute with a value string, can be called multiple times for the
	// same attrname.
	SetAttribute(attrname, value string) Queryable

	// GetAttribute for attrname, since more than one value can be set on the
	// attribute, return a slice of values.
	GetAttribute(attrname string) []string

	// GetAttributes return a map of all attributes set on this node.
	GetAttributes() map[string][]string
}
```

There are two aspects to a node that are important for `selector`
specification:

1. **Name**, name of the node, node names are case-insensitive, should begin
   with English alphabet, and contain only alphanumeric characters.
2. **Attributes**, any number of attributes can be attached to a node. Node
   attributes are case-insensitive, should begin with English alphabet, and
   contain only alphanumeric characters.

**node name**

Each node in the syntax-tree, that are constructed using the same tokenizer
or combinator, can be given a unique name. For instance, with goparsec:

```go
equal := parsec.Atom(`=`, "EQUAL") // parse comma as a terminal token.
```

The second argument `EQUAL` is the name of the tokenizer. And all nodes
constructed using this tokenizer will be named as `EQUAL`.

Similarly, to construct nonterminal-node `tagopen`.

```go
tagopen := ast.And("tagopen", nil, tagobrk, tagname, attrs, tagcbrk)
```

The first argument to the `And` combinator is the name of this combinator.
And all intermediate-nodes constructed using this combinator will be named
as `tagopen`.

**node attributes**

The second aspect of a node is its `attributes`. Each node can have any
number of attributes attached to a node. Some attributes are automatically
attached by tokenizers and combinators, these are called default-attributes,
while others can be attached using the Queryable API SetAttribute().

In some sense, node attributes can be seen as {key,[]value} properties of a
node, where key is the node's attribute-name and value is the
attribute-value. Since more than one value can be set for the same attribute
we are denoting it as `[]value` (array of value).

Default attributes
------------------

**class attribute**

Every node carry at least one class attribute. If it is intermediate-node,
its `class` attribute is set to `nonterm`.  If it is leaf-node,
its `class` attribute is set to `term`. User specified values for `class`
attribute should start with English character and contain - alphabets,
numbers, hyphen and underscore.

**value attribute**

Every node has an underlying value which is a sub-set of parsed input-text.
For a leaf-node, `value` is the text matched by the regular-expression
used in tokenizer. For a intermediate-node, `value` is concatenation
of all leaf-nodes' values descending from that intermediate-node.

User-Attributes
---------------

User attributes can be programmatically accessed using `Queryable`
behavior. More specifically, APIs like GetAttribute(), GetAttributes()
and SetAttribute() can be used for accessing node's attributes.

Among the user-attributes, **id attribute** is treated as special. Because,
like class, there is a short-hand notation for id. Similar to `class`
attribute, user specified value for `id` attribute should start with
English character, and contain - alphabets, numbers, hyphen and underscore.

Selector syntax for querying AST
-------------------------------

Scope of AST Query is to query syntax-tree for desired set of nodes, the query
result, if successful, will return an iterable on selected nodes. In that
sense, AST query is simply a `selector` specification into syntax-tree,
similar to [CSS selectors](https://www.w3schools.com/cssref/css_selectors.asp)
into HTML DOM.

Once we are comfortable with the concepts of, `syntax-tree`, `leaf-node`,
`intermediate-node`, `name`, `attributes`, `value`, and `class`, we can
use CSS like selector syntax to query for nodes within the Abstract Syntax
Tree.

To begin with, let us query for all textual content found in the our example
HTML.

```go
  ch := make(chan Queryable, 100)
  go ast.Query("TEXT", ch)
  for node := range ch {
    fmt.Println(node.GetValue())
  }
  // Output:
  // My First Heading
  // My first paragraph.
```

**Note that node-name is equivalent to html tag-name**

To query for all terminal nodes, which actually make up the entire HTML input
other than white space, we can use the `class` attribute.

```go
  ch := make(chan Queryable, 100)
  go ast.Query(".term", ch)
  for node := range ch {
    fmt.Printf("%s", node.GetValue())
  }
  fmt.Println()

  // Output:
  // <html><body><h1>My First Heading</h1><p>My first paragraph.</p></body></html>
```

Let us try somthing more fancy. We will fetch an example site's landing page
and gather all the hyper-links found there.

```go
  ast := NewAST("html", 100)
  y := makehtmly(ast)
  resp, _ := http.Get("https://example.com/")
  data, _ := ioutil.ReadAll(resp.Body)

  s := NewScanner(data).TrackLineno()
  ast.Parsewith(y, s)

  ch := make(chan Queryable, 100)
  go ast.Query("attrunquoted,attrsingleq,attrdoubleq", ch)
  for node := range ch {
      cs := node.GetChildren()
      if cs[0].GetValue() != "href" {
          continue
      }
      if len(cs) == 3 {
          fmt.Println(cs[2].GetValue())
      } else {
          fmt.Println(cs[3].GetValue())
      }
  }
```

Full-list of selector specification
-----------------------------------

```text

Selector              | Example               | Description
----------------------|-----------------------|---------------------------------
.class                | .term                 | Selects all terminal nodes.
#id                   | #firstname            | Selects the node with
                      |                       | id="firstname".
*                     | *                     | Selects all nodes.
node,                 | comma                 | Selects all `comma` nodes.
node, node            | comma, equal          | Selects all `comma` nodes and
                      |                       | all `equal` nodes.
node node             | attr equal            | Selects all `equal` nodes inside
                      |                       | `attr`.
node > node           | tag > tagname         | Selects all `tagname` node where
                      |                       | the parent is a `tag` node.
node + node           | oanglebrkt + tagname  | Selects all `tagname` node that
                      |                       | are placed immediately after
                      |                       | `oanglebrkt` elements.
node ~ node           | tagname ~ canglebrkt  | Selects every `tagname` node that
                      |                       | are preceded by `canglebrkt` node.
[attribute]           | [ignore]              | Selects all nodes with a
                      |                       | ignore attribute.
[attribute=value]     | [title=xyz]           | Selects all nodes whose `title`
                      |                       | attribute value is `xyz`.
[attribute~=value]    | [title~=flower]       | Selects all nodes with a `title`
                      |                       | attribute containing the word
                      |                       | `flower`.
[attribute^=value]    | tagname[title^=in]    | Selects every `tagname` node
                      |                       | whose title attribute value
                      |                       | begins with `in`.
[attribute$=value]    | file[path$=.pdf]      | Selects every `file` node whose
                      |                       | path attribute ends with `.pdf`.
[attribute*=value]    | file[path*=usr|opt]   | Selects every `file` node whose
                      |                       | path attribute value matches
                      |                       | regular expression `usr|opt`
:empty                | file:empty            | Selects every `file` node that
                      |                       | has no children.
:first-child          | comma:first-child     | Selects every `comma` node that
                      |                       | is the first child of its parent.
:first-of-type        | comma:first-of-type   | Selects every `comma` node that
                      |                       | is the first `comma` node of
                      |                       | its parent.
:last-child           | comma:last-child      | Selects every `comma` node that
                      |                       | is the last child of its parent.
:last-of-type         | comma:last-of-type    | Selects every `comma` node that
                      |                       | is the last `comma` node of its
                      |                       | parent.
:nth-child(n)         | comma:nth-child(2)    | Selects every `comma` node that
                      |                       | is the second child of its
                      |                       | parent.
:nth-last-child(n)    | eq:nth-last-child(2)  | Selects every `eq` node that
                      |                       | is the second child of its
                      |                       | parent, counting from the last
                      |                       | child.
:nth-last-of-type(n)  | eq:nth-last-of-type(2)| Selects every `eq` node that
                      |                       | is the second `eq` node of
                      |                       | its parent, counting from the
                      |                       | last child.
:nth-of-type(n)       | eq:nth-of-type(2)     | Selects every `eq` node that
                      |                       | is the second `eq` node of
                      |                       | its parent.
:only-of-type         | comma:only-of-type    | Selects every `comma` node that
                      |                       | is the only `comma` node of its
                      |                       | parent.
:only-child           | comma:only-child      | Selects every `comma` node that
                      |                       | is the only child of its parent.
```


[lalr-link]: https://en.wikipedia.org/wiki/LALR_parser
[parser-combinator-link]: https://en.wikipedia.org/wiki/Parser_combinator
[goparsec-link]: https://github.com/prataprc/goparsec
[goparsec-godoc-link]: https://godoc.org/github.com/prataprc/goparsec
[ast-link]: https://en.wikipedia.org/wiki/Abstract_syntax_tree
