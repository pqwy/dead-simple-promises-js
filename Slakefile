
run = (cmd, next) ->
  { exec } = require 'child_process'
  exec cmd, (err, stdout, stderr) ->
    case err? => throw err
    case stderr.length or stdout.length =>
      console.log stderr, stdout
      next?!
    case _ => next?!

build = (next) ->
  run 'lsc --compile --output lib/ src/', next

test = (next) ->
  run 'node_modules/.bin/mocha -c --compilers ls:LiveScript', next

task \build, 'rebuild sources', build
task \test, 'tests', -> build test

