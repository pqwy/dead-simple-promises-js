
# Dead-Simple Promises, js #

Yet **another** future/promise implementation for Javascript.

![PROMISE!](https://raw.github.com/pqwy/dead-simple-promises-js/memorabilia/brofist.jpg)

The distinction of this one is very simple semantics, supported by some
equational laws, and a pretty fast implementation. The goal is to have promises
that can wrap every single async call in an IO-heavy node application and still
survive the speed hit, together with being relatively no-brainer to use.

Currently, the hit is around 40% for pure in-process workloads and much lower
with intermittent syscalls. See `slake bench`.

On the other hand, it is **not** compatible with
[Promises/A+](http://promises-aplus.github.io/promises-spec/). Continuations are
not invoked strictly _after_ `.then` method returns (they could be invoked
_during_ that call), which means the burden of not smashing the stack is on the
user. As a minor divergence, `.then` also handles only chaining of success:
`onError` registers failure listeners, as this operation has imperative
semantics.

## Documentation ##

**TODO**, but the single source file is short and documented. It also includes
some laws the promises satisfy.

## Like so: ##

Given a path, return paths and sizes of filesystem objects for the filesystem subtree:

```javascript
var promise = require('dead-simple-promises'),
    fsp     = promise.owrap(require('fs')),
    util    = require('util');

function fileSizes (path) {
  return fsp.stat(path).then(function (stat) {
    if (stat.isDirectory()) {
      return fsp.readdir(path).then(function (files) {
        for (var i = 0; i < files.length; i++) {
          files[i] = fileSizes(path + "/" + files[i]);
        }
        return promise.seq(files).then(function (subtree) {
          return { path: path, stat: stat.size, sub: subtree }
        });
      });
    } else {
      return promise( { path: path, size: stat.size } );
    }
  });
}

fileSizes (wherever)
  .then (function (tree) { console.log ('x', tree); })
  .onError (function (err) { console.error (err); })

```

```livescript
require! { promise: \dead-simple-promises, util }
fsp = promise.owrap require \fs

file-sizes = (path) ->
  {size}: stat <- fsp.stat path .then
  if stat.is-directory!
    files <- fsp.readdir path .then
    files |> map -> file-sizes "#path/#it"
          |> promise.seq |> (.then -> {path, size, sub: it})
  else promise {path, size}

file-sizes wherever .then     (util.inspect >> console.log)
                    .on-error console.error
```
