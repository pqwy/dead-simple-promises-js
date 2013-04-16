require! promise: '../lib/promise', p: \prelude-ls
require! [ \fs, \assert ]

fsp = promise.owrap fs
        ..touch = promise.fwrap (file, cb) ->
            fs.write-file file, '', cb

eet = global.it

exn = (e) ->
  case e instanceof Error => e
  case _ => new Error e


describe \promise, ->

  describe \events, ->

    eet 'should succeed in failing', (done) ->
      p = promise!
      p.on-error     !-> done!
      p.on-completed !-> done exn \nope
      process.next-tick -> ( p.reject \because ; p.complete \yup )

    eet 'should not fail in succeeding pt. 1', (done) ->
      p = promise!
      p.on-error     !-> done exn \nope
      p.on-completed !-> done!
      process.next-tick -> ( p.complete \yup ; p.reject \because )

    eet 'should not fail in succeeding pt. 2', (done) ->
      p = promise 19
      process.next-tick -> ( p.reject ; p.complete \because )
      p.on-completed !(x) ->
        process.next-tick ->
          case x is 19 => done!
          case _       => done exn \nope

  describe \composition, ->

    eet 'should respect then as map', (done) ->
      promise "foo"
        .then (+ "bar")
        .then ->
          case it is "foobar" => done!
          case _              => done exn it

    eet 'should respect then as >>=', (done) ->
      promise "foo"
        .then -> promise it + "bar"
        .then ->
          case it is "foobar" => done!
          case _              => done exn it

    eet 'should chain failure, pt. 1', (done) ->
      p  = promise!
      p2 = p.then -> "ok"
      p2.on-error     !-> done!
      p2.on-completed !-> done exn "promise completed"
      p.reject \bzz

    eet 'should chain failure, pt. 2', (done) ->
      p = promise "foo"
          .then ->
            p2 = promise!
            process.next-tick -> p2.reject \nope
            p2
      p.on-error     !-> done!
      p.on-completed !-> done exn "promise completed"

    eet 'should #chain', (done) ->
      promise "foo" .chain do
        * (+ "bar")
        * (+ "baz")
      .then (x) ->
        case x is "foobarbaz" => done!
        case _                => done exn x
      .on-error done

    eet 'should #chain failure', (done) ->
      promise "foo" .chain do
        * (+ "bar")
        * -> p = promise! ; (process.next-tick -> p.reject \nope) ; p
        * (+ "baz")
      .then (x) -> done exn x
      .on-error (err) ->
        case err is \nope => done!
        case _            => done exn err

  describe 'instance goodies', ->

    eet 'can accept callbacks and win by winning', (done) ->
      p = promise!
      p.cb (err, res) ->
        case err? => done exn err
        case res? => done!
      p.complete \win

    eet 'can accept callbacks and win by failing', (done) ->
      p = promise!
      p.cb (err, res) ->
        case err? => done!
        case res? => done exn res
      p.reject \win

    eet 'can timeout, pt.1', (done) ->
      p = promise!
      p.timeout 5
        .then     -> done!
        .on-error -> done exn it
      set-timeout (-> p.complete \bzzz), 1

    eet 'can timeout, pt.2', (done) ->
      p = promise!
      p.timeout 1
        .then     -> done exn it
        .on-error ->
          case it is \timeout => done!
          case _              => done exn it
      set-timeout (-> p.complete \bzzz), 5

  describe 'module goodies', ->

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

