
require! promise: '../lib/promise', p: \prelude-ls
require! \fs

fsp = promise.owrap fs

pmap = !(fn, arr, next) ->
  case p.empty arr => next null, []
  case _ =>
    n = arr.length ; resn = [] ; dead = false
    for e, i1 in arr then do (i = i1) ->
      fn e, !(err, res) ->
        case err and dead =>
        case err          => dead := true ; next err
        case --n is 0     => resn[i] = res ; next null, resn
        case _            => resn[i] = res

on-error = (fail, succ) -> (err, res) ->
  case err => fail err
  case _   => succ res

walk-fs-cb = (path, fn, next) ->
  fs.lstat path, next `on-error` (stat) ->
    if stat.is-directory!
      fs.readdir path, next `on-error` (files) ->
        pmap do
          * (file, next) -> walk-fs-cb "#path/#file", fn, next
          * files
          * next `on-error` -> next null, fn path, stat, it
    else next null, fn path, stat

walk-fs-p = (path, fn) ->
  stat <- fsp.lstat path .then
  if stat.is-directory! =>
    files <- fsp.readdir path .then
    files |> p.map (file) -> walk-fs-p "#path/#file", fn
          |> promise.seq
          |> (.then -> fn path, stat, it)
  else promise( fn path, stat or null )

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

visit-tree-cb2 = (n, tree, next) ->
  case n > 1000     => set-immediate ->
    visit-tree-cb2 0, tree, next
  case tree is \tip => next null, 1
  case _            => pmap do
    (t, n) -> visit-tree-cb2 (n+1), t, n
    tree
    (err, counts) -> next null, 1 + p.sum counts

visit-tree-p2 = (n, tree) ->
  case n > 1000     => promise.set-immediate!then -> visit-tree-p2 0, tree
  case tree is \tip => promise 1
  case _            =>
    tree |> p.map -> visit-tree-p2 (n+1), it
         |> promise.seq |> (.then -> 1 + p.sum it)


do ->
  walk-path = "/usr/lib/node_modules"

  suite "fs crawl ( #walk-path )", ->

    bench "callbacks", (done) ->
      walk-fs-cb walk-path, (->), (-> throw it) `on-error` done

    bench "promise", (done) ->
      walk-fs-p walk-path, (->) .then done .on-error -> throw it

  tree = make-tree 8, 3

  suite "struct crawl, delayed leaves", ->

    bench "callbacks", (done) -> visit-tree-cb tree, done

    bench "promise", (done) -> visit-tree-p tree .then done

  suite "struct crawl, immediate leaves", ->

    bench "callbacks", (done) ->
      visit-tree-cb2 0, tree, -> set-immediate done

    bench "promise", (done) ->
      visit-tree-p2 0, tree .then -> set-immediate done

