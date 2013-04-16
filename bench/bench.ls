
require! promise: '../lib/promise', p: \prelude-ls
require! \fs

fsp = promise.owrap fs

pmap = !(fn, arr, next) ->
  case p.empty arr => next null, []
  case _ =>
    n = p.length arr ; resn = [] ; dead = false
    for e, i1 in arr then do (i = i1) ->
      fn e, !(err, res) ->
        case err and dead =>
        case err          => dead := true ; next err
        case --n is 0     => resn[i] = res ; next null, resn
        case _            => resn[i] = res

walk-fs-cb = (path, fn, next) ->
  fs.lstat path, (err, stat) ->
    case err                => next err
    case stat.is-directory! =>
      fs.readdir path, (err, files) ->
        case err => next err
        case _   => pmap do
          * (file, next) -> walk-fs-cb "#path/#file", fn, next
          * files
          * (err, children) -> next err, (fn path, stat, children)
    case _ => next null, (fn path, stat)

walk-fs-p = (path, fn) ->
  stat <- fsp.lstat path .then
  if stat.is-directory! =>
    files <- fsp.readdir path .then
    files |> p.map (file) -> walk-fs-p "#path/#file", fn
          |> promise.seq
          |> (.then -> fn path, stat, it)
  else fn path, stat

make-tree = (n, k) ->
  case n is 0 => \tip
  case _      => [ make-tree (n - 1), k for i from 1 to k ]

visit-tree-cb = (tree, next) ->
  case tree is \tip => set-immediate -> next null, 1
  case _            =>
    pmap visit-tree-cb, tree, (err, counts) ->
      next null, 1 + p.sum counts

visit-tree-p = (tree) ->
  case tree is \tip => promise.set-immediate 1
  case _            =>
    tree |> p.map visit-tree-p
         |> promise.seq |> (.then -> 1 + p.sum it)

do ->
  walk-path = "/usr/lib/node_modules"

  suite "fs crawl ( #walk-path )", ->

    bench "callbacks", (next) ->
      (err, res) <- walk-fs-cb walk-path, (->)
      if err then throw "ERROR: #err" else next!

    bench "promise", (next) ->
      walk-fs-p walk-path, (->) .then next .on-error -> throw it

  tree = make-tree 8, 3

  suite "struct crawl", ->

    bench "callbacks", (next) ->
      visit-tree-cb tree, next

    bench "promise", (next) ->
      visit-tree-p tree .then next

