// lang-basics-go-check — DETERMINISTIC check for LB-2 (Go ctx propagation), via go/ast.
//
// It flags calls to context.Background() / context.TODO() inside functions other than
// main / init. Outside those entry/bootstrap points, fabricating a fresh root context is the
// common shape of "I dropped the caller's ctx instead of propagating it" — losing
// cancellation, deadline, and trace propagation.
//
// It resolves the local name bound to the "context" package per file, so an aliased import
// (`import ctx "context"`) and a dot-import (`. "context"`) are both handled, not evaded.
//
// This is a deterministic PROXY, not a full "exported IO function missing ctx param" check
// (that needs go/types to know which calls are I/O). A clean run does NOT prove every function
// propagates ctx correctly. Accepted residuals (fixing them would false-positive on legit
// usage): a closure/goroutine INSIDE main/init that calls context.Background() is not flagged
// (often a legit background worker rooted at startup); a helper that returns
// context.Background() and is called elsewhere is not traced; a local identifier shadowing the
// context alias / dot-imported Background could in principle false-positive (rare).
//
// Scope: pass service / handler / repository / client Go files or directories. *_test.go is
// skipped (directory scan AND explicit file args); vendor/.git/testdata/node_modules dirs are
// skipped.
//
// INVOCATION: scan DIRECTORIES with `go run` — `go run lang-basics-go-check.go ./internal/svc`.
// `go run` consumes trailing `.go` FILE args as additional package sources, so to scan
// individual files build a binary first:
//
//	go build -o /tmp/lbgo lang-basics-go-check.go && /tmp/lbgo a.go b.go
//
// Exit: 0 no finding; 1 finding(s); 2 setup/inconclusive (missing path, non-.go file, dir with
// no non-test .go, no non-test file in scope, walk error, or a parse error — NEVER clean).
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func setupErr(msg string) {
	fmt.Fprintf(os.Stderr, "lang-basics-go: %s — inconclusive\n", msg)
	os.Exit(2)
}

// Exempt by NAME: main / init. (A `func main` declared in a non-main package is exempted too —
// a documented name-based carve-out; such code is unusual and not worth a package-name check.)
// Test*/Benchmark*/Example*/Fuzz* are NOT exempted: _test.go files are skipped wholesale at
// collection, and a production function merely NAMED TestX must still be scanned.
func isEntryFunc(name string) bool {
	return name == "main" || name == "init"
}

func skipDir(name string) bool {
	switch name {
	case "vendor", ".git", "testdata", "node_modules":
		return true
	}
	return false
}

func collect(paths []string) []string {
	var files []string
	for _, p := range paths {
		info, err := os.Stat(p)
		if err != nil {
			setupErr("path not found: " + p)
		}
		if info.IsDir() {
			n := 0
			werr := filepath.Walk(p, func(path string, fi os.FileInfo, e error) error {
				if e != nil {
					return e
				}
				if fi.IsDir() {
					if skipDir(fi.Name()) {
						return filepath.SkipDir
					}
					return nil
				}
				if strings.HasSuffix(path, ".go") && !strings.HasSuffix(path, "_test.go") {
					files = append(files, path)
					n++
				}
				return nil
			})
			if werr != nil {
				setupErr("walk error under " + p + ": " + werr.Error())
			}
			if n == 0 {
				setupErr("no non-test .go files under directory: " + p)
			}
		} else {
			if !strings.HasSuffix(p, ".go") {
				setupErr("not a .go file: " + p)
			}
			if strings.HasSuffix(p, "_test.go") {
				continue
			}
			files = append(files, p)
		}
	}
	if len(files) == 0 {
		setupErr("no non-test .go files in scope")
	}
	return files
}

// contextNames returns the local identifiers that refer to the "context" package in this file,
// plus whether it was dot-imported.
func contextNames(node *ast.File) (map[string]bool, bool) {
	names := map[string]bool{}
	dot := false
	for _, imp := range node.Imports {
		// Unquote handles both interpreted ("context") and raw (`context`) import-path strings.
		path, err := strconv.Unquote(imp.Path.Value)
		if err != nil || path != "context" {
			continue
		}
		switch {
		case imp.Name == nil:
			names["context"] = true
		case imp.Name.Name == ".":
			dot = true
		case imp.Name.Name != "_":
			names[imp.Name.Name] = true
		}
	}
	return names, dot
}

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: go build -o /tmp/lbgo lang-basics-go-check.go && /tmp/lbgo <path> [...]  (or: go run lang-basics-go-check.go <DIR>)")
		os.Exit(2)
	}
	files := collect(args)
	fset := token.NewFileSet()
	hits := 0
	for _, f := range files {
		node, err := parser.ParseFile(fset, f, nil, 0)
		if err != nil {
			setupErr(fmt.Sprintf("parse error %s: %v", f, err))
		}
		ctxNames, dot := contextNames(node)
		if len(ctxNames) == 0 && !dot {
			continue // file does not import context; it cannot call context.Background/TODO
		}
		flag := func(call *ast.CallExpr, where string) {
			label := ""
			switch fe := call.Fun.(type) {
			case *ast.SelectorExpr:
				if pkg, ok := fe.X.(*ast.Ident); ok && ctxNames[pkg.Name] &&
					(fe.Sel.Name == "Background" || fe.Sel.Name == "TODO") {
					label = "context." + fe.Sel.Name
				}
			case *ast.Ident:
				if dot && (fe.Name == "Background" || fe.Name == "TODO") {
					label = "context." + fe.Name + " (dot-import)"
				}
			}
			if label != "" {
				pos := fset.Position(call.Pos())
				fmt.Printf("lang-basics-go smell: %s:%d: %s() in %s — propagate the caller's ctx, do not fabricate a root ctx\n",
					f, pos.Line, label, where)
				hits = 1
			}
		}
		scan := func(root ast.Node, where string) {
			ast.Inspect(root, func(m ast.Node) bool {
				if call, ok := m.(*ast.CallExpr); ok {
					flag(call, where)
				}
				return true
			})
		}
		// Scan non-entry function bodies AND package-level declarations (var/const
		// initializers have no enclosing function — `var bg = context.Background()`).
		// main/init bodies are skipped (accepted residual: a closure there is often a legit
		// background worker).
		for _, decl := range node.Decls {
			switch d := decl.(type) {
			case *ast.FuncDecl:
				if d.Body == nil || isEntryFunc(d.Name.Name) {
					continue
				}
				scan(d.Body, d.Name.Name)
			case *ast.GenDecl:
				scan(d, "<package-level>")
			}
		}
	}
	os.Exit(hits)
}
