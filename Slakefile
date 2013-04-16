
bin = (exe) -> "node_modules/.bin/#exe"

run = (cmd, args, next) ->
  { spawn } = require 'child_process'
  spawn cmd, args, stdio: \inherit
    ..on \close, -> next?!


build = (next) ->
  run (bin \lsc), <[--compile --output lib/ src/]>, next

test = (next) ->
  run (bin \mocha), <[-c --compilers ls:LiveScript]>, next

bench = ->
  <- run 'lsc', <[--compile --output bench/ bench/]>
  run (bin \matcha), <[bench/bench.js]>

task \build, 'rebuild sources',    build
task \test , 'tests'          , -> build test
task \bench, 'benchmark'      , -> build bench

