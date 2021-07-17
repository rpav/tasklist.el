((common
  (:cwd "/tmp")
  (:env "FOO=BAZ")
  (:window "Testing Tasklist!"))
 (tasks
  (run
   (:name "Run")
   (:command "(echo $PWD; echo foo: $FOO)")
   (:env "FOO=BAR"))))
