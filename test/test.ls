require! promise: '../lib/promise', p: \prelude-ls
require! [ \fs, \assert ]

fsp = promise.owrap fs
        ..touch = promise.fwrap (file, cb) ->
            fs.write-file file, '', cb

eet = global.it

exn = (e) ->
  case e instanceof Error => e
  case _ => new Error e

next-tick = process.next-tick

describe \promise, ->


  describe \events, ->

    eet 'should succeed in failing', (done) ->

      p = promise!
      p.on-error     !-> done!
      p.on-completed !-> done exn \nope
      next-tick !-> p.reject \because ; p.complete \yup

    eet 'should not fail in succeeding (late complete)', (done) ->

      p = promise!
      p.on-error     !-> done exn \nope
      p.on-completed !-> done!
      next-tick !-> p.complete \yup ; p.reject \because

    eet 'should not fail in succeeding (early complete)', (done) ->

      p = promise 19
      next-tick -> p.reject \because ; p.complete \yup
      p.on-completed !->
        next-tick !->
          case p._x is 19 => done!
          case _          => done exn \nope
      .on-error !-> done exn \nope


  describe \composition, ->

    describe \then, ->

      eet 'as map', (done) ->

        promise "foo" .then (+ "bar") .then ->
          case it is "foobar" => done!
          case _              => done exn it

      eet 'as >>=', (done) ->

        promise "foo" .then (+ "bar") >> promise .then ->
          case it is "foobar" => done!
          case _              => done exn it

      eet 'chain failure ( left )', (done) ->

        ( promise.create((ok, nok) -> next-tick -> nok \bzz).then -> \ok )
          ..on-error     !-> done!
          ..on-completed !-> done exn "promise completed"

      eet 'chain failure ( right )', (done) ->

        ( promise "foo" .then ->
            promise.create (ok, nok) ->
              next-tick -> nok \nope )
          ..on-error     !-> done!
          ..on-completed !-> done exn "promise completed"

    describe \else, ->

      eet 'bypasses on success', (done) ->

        promise.create (ok) -> next-tick -> ok \xx
        .else -> done exn "else followed after success"
        .then ->
          case it is \xx => done!
          case _         => done exn it

      eet 'fires on failure', (done) ->

        promise.create (ok, nok) -> next-tick -> nok \derp
        .then     -> done exn "first then"
        .else     -> done!
        .on-error -> done exn "error propagated"

      eet 'acts as map', (done) ->

        promise.create (ok, nok) -> next-tick -> nok \derp
        .else -> \foo
        .then ->
          case it is \foo => done!
          case _          => done exn it
        .on-error -> done exn it

      eet 'acts as >>= over errors ( + )', (done) ->

        promise.create (ok, nok) -> next-tick -> nok \derp
        .else -> promise \foo
        .then ->
          case it is \foo => done!
          case _          => done exn it
        .on-error -> done exn it

      eet 'acts as >>= over errors ( - )', (done) ->

        promise.create (ok, nok) -> next-tick -> nok \a
        .else -> promise.create (ok, nok) -> next-tick -> nok \b
        .then -> done "we came through?"
        .on-error ->
          case it is \b => done!
          case _        => done exn it

    describe 'thread', ->

      eet '( + )', (done) ->

        promise "foo" .thread do
          * (+ "bar")
          * (+ "baz")
        .then (x) ->
          case x is "foobarbaz" => done!
          case _                => done exn x
        .on-error done

      eet '( - )', (done) ->

        promise "foo" .thread do
          * (+ "bar")
          * -> p = promise! ; next-tick(-> p.reject \nope) ; p
          * (+ "baz")
        .then (x) -> done exn x
        .on-error (err) ->
          case err is \nope => done!
          case _            => done exn err


  describe 'instance goodies:', ->

    describe 'accepts callbacks', ->

      eet '( + )', (done) ->

        p = promise!
        p.cb (err, res) ->
          case err? => done exn err
          case res? => done!
        p.complete \win

      eet '( - )', (done) ->

        p = promise!
        p.cb (err, res) ->
          case err? => done!
          case res? => done exn res
        p.reject \win

    describe 'timeouts', ->

      eet '( + )', (done) ->

        p = promise!
        p.timeout 5
        .then     -> done!
        .on-error -> done exn it
        set-timeout (-> p.complete \bzzz), 1

      eet '( - )', (done) ->

        p = promise!
        p.timeout 1
        .then     -> done exn it
        .on-error ->
          case it is \timeout => done!
          case _              => done exn it
        set-timeout (-> p.complete \bzzz), 5

    eet 'can be a little slow, if need be', (done) ->

      tick = null
      promise \all-the-things .then-later ->
        case not tick => done exn "Too fast."
        case _        => done!
      tick = \tock

    describe 'can act like its silly little sister', ->

      eet '( + )', (done) ->

        tick = null
        promise \all-the-things .to-aplus!.then ->
          case not tick => done exn "Too fast."
          case _        => done!
        tick = \tock

      eet '( - )', (done) ->

        tick = null
        p = promise!
        p.to-aplus!then null, ->
          case not tick => done exn "Too fast."
          case _        => done!
        p.reject \because
        tick = \tock


  describe 'module goodies', ->

    describe 'creation bracket', ->

      eet "( + )", (done) ->

        ( promise.create (ok, nok) ->
            set-immediate -> ok \ok )
          .then ->
            case it is \ok => done!
            case _         => done it
          .on-error -> done it

      eet "( - )", (done) ->

        ( promise.create (ok, nok) ->
            set-immediate -> nok \nok )
          .then -> done it
          .on-error ->
            case it is \nok => done!
            case _          => done it

    describe 'threading', ->

      eet '( + )', (done) ->

        promise.thread do
          * -> "foo"
          * (+ "bar")
          * (+ "baz")
        .then (x) ->
          case x is "foobarbaz" => done!
          case _                => done exn x
        .on-error done

      eet '( - )', (done) ->

        promise.thread do
          * -> "foo"
          * (+ "bar")
          * -> p = promise! ; next-tick(-> p.reject \nope) ; p
          * (+ "baz")
        .then (x) -> done exn x
        .on-error (err) ->
          case err is \nope => done!
          case _            => done exn err

    describe 'wrapping', ->

      eet 'passes promises', (done) ->
        p1 = promise 666
        if promise.wrap p1 is p1 then done! else done exn "promise.wrap(promise)"

      eet 'wraps values', (done) ->
        ok = false
        promise.wrap 666 .then -> ok := true ; done!
        process.next-tick -> done exn "promise.wrap(value)" unless ok

      eet 'wraps undefined', (done) ->
        [ ok, und ] = [ false, (->)! ]
        promise.wrap und .then -> ok := true ; done!
        process.next-tick -> done exn "promise.wrap(undefined)" unless ok


    fs-tree =
      rm-tree : (path) ->
        stat <- fsp.lstat path .then
        if stat.is-directory!
            files <- fsp.readdir path .then
            <- promise.seq_ [ fs-tree.rm-tree "#{path}/#{file}" for file in files ]
                      .then
            fsp.rmdir path
        else fsp.unlink path

      build-tree : (path, obj) ->
        fsp.mkdir path .then ->
          for k, e of obj
            if typeof! e is \Object => fs-tree.build-tree "#path/#k", e
            else fsp.write-file "#path/#k", ( e?.to-string?! ? '' )


    temp = "/tmp/promise-test-temp-#{process.pid}-#{new Date!get-time!}"

    before (done) ->
      fs.mkdir temp, (err, res) ->
        case err? => done exn err
        case _    => done!

    after (done) ->
      fs-tree.rm-tree temp
      .then     -> done!
      .on-error -> done exn it

    eet "lifts functions", (done) ->

      promise.lift (+), 1, promise 2
      .then ->
        case it is 3 => done!
        case _       => done exn "wrong result: #it"
      .on-error -> done exn it

    eet 'knows how to chill', (done) ->

      t0 = new Date
      promise.after 5 .then (t1) ->
        case t1 - t0 >= 5 => done!
        case _            => done exn "#t0 - #t1"

    eet 'delays action in more than one way', (done) ->

      [1 to 10] |> p.map ->
        promise.seq [
          promise.set-immediate \si
          promise.next-tick \nt
          promise.after 0 .then -> \after
        ] .then -> assert.deep-equal it, [\si, \nt, \after]
      |> promise.seq_ |> (.then done)


    eet 'runs around', (done) ->

      rand-struct = (p-dir = 1) ->
        if Math.random! < p-dir
          {[ k, rand-struct (0.8 * p-dir) ] for k in <[eenie meenie moe]>}
        else \desu

      fs-tree.build-tree "#{temp}/random", rand-struct!
      .then     -> fs-tree.rm-tree "#{temp}/random"
      .then     -> done!
      .on-error -> done exn it

