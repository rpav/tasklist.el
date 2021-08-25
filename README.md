# Tasklist

Make a list of tasks (i.e. commands).  Run them in a window or in a separate frame.

```lisp
;;; This should be in a file named .tasklist.el in your project root.
;;; Nothing is eval'd.

((common
 (:cwd "...")
 (:env "X=Y" "A=B" ...)
 (tasks
  (build
   (:name "Build Project")
   (:command "make"))
  (run
   (:name "Run Project")
   (:command "make" "run")
   (:cwd "bin"))))
```

## Relevant commands

* `tasklist-run`: Run a task
* `tasklist-menu`: Pop up a menu with tasks
* `tasklist-set-project-root`: Set global project override path
* `tasklist-set-project-default`: Set project path to use if no other project is current

## Configuration

For now there isn't much configuration beyond the above.  Commands are in the following form:

```lisp
(:command "BINARY-NAME" "ARG0 ARG1 ...")
```

The `:name` is just a "pretty" name to display, and not strictly necessary.  If `:cwd` is specified, if it's `file-absolute-p`, it will be treated as an absolute path, otherwise will be relative to the project root (as determined by `projectile-project-root`).

There is also `:window`:

```lisp
(:window "Name")
```

This will call the *buffer* `*Task: Project/Name*`.  By using the same name for multiple tasks, you can cause the window to be shared/reused.  (By default, the given `:name` is used for each task.)

### Environment Variables

To set **environment** variables, use `:env`:

``` lisp
(:env "VAR=VALUE" ...)
```

### Tasklist Variable Substitution

To set *tasklist.el* "variables,", use `:variables` (only supported in the `:common` section, see below):

``` lisp
(:variables
  ("project" . "My Project")
  ("build"   . "Debug")
  ...)
```

These variables will be substituted in various strings throughout tasklist:

``` lisp
(:window "Testing %project")
(:cwd "build/%compiler-%build/")
```

For a literal `%`, escape it as `\%`.

### Common

The `common` section does what it likely implies: sets default values for all tasks.  Tasks may of course override these.  Currently, `:env`, `:cwd`, `:window`, and `:variables` are supported.

## Binding keys

If you want to bind keys, you can put things in your `init.el` or wherever (but, obviously not in `.tasklist.el`):

```lisp
(global-set-key (kbd "f7") (lambda () (interactive) (tasklist-run 'build)))
```

## Obviously

This is more or less [cmake-build.el](https://github.com/rpav/cmake-build.el) with all the cmake stuff ripped out, and all the window and frame-handling things left .. which is a sizeable portion.

## License

GPL3
