
done = -> \xx

run = (cmd, next) ->
  { exec } = require 'child_process'
  exec cmd, (err, stdout, stderr) ->
    throw err if err?
    console.log stderr, stdout
    next?!

task \build, 'rebuild sources', ->
  run 'lsc --compile --output lib/ src/', done
