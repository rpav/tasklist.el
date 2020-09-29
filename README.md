# Tasklist

Make a list of tasks (i.e. commands).  Run them in a window or in a separate frame.

```lisp
;;; This should be in a file named .tasklist.el in your project root.
;;; Nothing is eval'd.

((tasks
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

## Binding keys

If you want to bind keys, you can put things in your `init.el` or wherever (but, obviously not in `.tasklist.el`):

```lisp
(global-set-key (kbd "f7") (lambda () (interactive) (tasklist-run 'build)))
```

## Obviously

This is more or less [cmake-build.el](https://github.com/rpav/cmake-build.el) with all the cmake stuff ripped out, and all the window and frame-handling things left .. which is a sizeable portion.

(I've moved to using [Grunt](https://gruntjs.com/) and a (current-unreleased) custom grunt-cmake module to replace `cmake-build.el`, so build tasks and other non-cmake tasks can be unified and not editor-dependent.  This is the editor glue.)

## License

GPL3
