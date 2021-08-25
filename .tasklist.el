((common
  (:cwd "/%d")
  (:env "FOO=BAZ")
  (:window "Testing %P!")
  (:variables
   ("P" . "Tasklist")
   ("d" . "tmp")
   ("foo" . "baz")))
 (tasks
  (run
   (:name "Run")
   (:command "(echo $PWD; echo \\$FOO: $FOO; echo \\%foo: %foo)")
   (:env "FOO=BAR"))))
