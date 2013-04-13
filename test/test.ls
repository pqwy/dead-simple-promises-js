require! promise: '../lib/promise'
require! [\assert, \fs]

fsp = promise.owrap fs
        ..touch = promise.fwrap (file, cb) ->
            fs.write-file file, '', cb

eet = global.it


describe \promise, ->

  describe \events, ->

    eet 'should succeed in failing 1', (done) ->
      p = promise!
      p.on-error !-> done!
      process.next-tick -> ( p.reject \because ; p.complete \yup )

    eet 'should not fail in succeeding pt. 1', (done) ->
      p = promise!
      p.on-completed !-> done!
      process.next-tick -> ( p.complete \yup ; p.reject \because )

    eet 'should not fail in succeeding pt. 2', (done) ->
      p = promise 19
      process.next-tick -> ( p.reject ; p.complete \because )
      p.on-completed !(x) ->
        process.next-tick ->
          case x is 19 => done!
          case _       => done \nope

  describe \composition, ->

    eet 'should respect then as map', (done) ->
      promise "foo"
        .then (+ "bar")
        .then ->
          case it is "foobar" => done!
          case _              => done it

    eet 'should respect then as >>=', (done) ->
      promise "foo"
        .then -> promise it + "bar"
        .then ->
          case it is "foobar" => done!
          case _              => done it

    eet 'should chain failure, pt. 1', (done) ->
      p  = promise!
      p2 = p.then -> "ok"
      p2.on-error     !-> done!
      p2.on-completed !-> done "promise completed"
      p.reject \bzz

    eet 'should chain failure, pt. 2', (done) ->
      p = promise "foo"
          .then ->
            p2 = promise!
            process.next-tick -> p2.reject \nope
            p2
      p.on-error     !-> done!
      p.on-completed !-> done "promise completed"

    eet 'should #seq', (done) ->
      promise "foo" .seq do
        * (+ "bar")
        * (+ "baz")
      .then (x) ->
        case x is "foobarbaz" => done!
        case _                => done x
      .on-error done

    eet 'should #seq failure', (done) ->
      promise "foo" .seq do
        * (+ "bar")
        * -> p = promise! ; (process.next-tick -> p.reject \nope) ; p
        * (+ "baz")
      .then (x) -> done x
      .on-error (err) ->
        case err is \nope => done!
        case _            => done err

  describe 'instance goodies', ->

    eet 'can accept callbacks and win by winning', (done) ->
      p = promise!
      p.cb (err, res) ->
        case err? => done err
        case res? => done!
      p.complete \win

    eet 'can accept callbacks and win by failing', (done) ->
      p = promise!
      p.cb (err, res) ->
        case err? => done!
        case res? => done res
      p.reject \win

    eet 'can timeout, pt.1', (done) ->
      p = promise!
      p.timeout 5
        .then     -> done!
        .on-error -> done it
      set-timeout (-> p.complete \bzzz), 1

    eet 'can timeout, pt.2', (done) ->
      p = promise!
      p.timeout 1
        .then     -> done it
        .on-error ->
          case it is \timeout => done!
          case _              => done it
      set-timeout (-> p.complete \bzzz), 5

  describe 'module goodies', ->

    temp = "/tmp/promise-test-temp-#{process.pid}-#{(new Date).get-time!}"

    before (done) ->
      fs.mkdir temp, (err, res) ->
        case err? => done err
        case _    => done!

    after (done) ->
      fsp.readdir temp
        .then (files) -> promise.pseq [ fsp.unlink "#{temp}/#{f}" for f in files ]
        .then     -> fsp.rmdir temp
        .then     -> done!
        .on-error -> done new Error it

    eet 'knows how to chill', (done) ->
      t0 = new Date
      promise.after 5 .then (t1) ->
        case t1 - t0 >= 5 => done!
        case _            => done [t0, t1]

    eet 'does stuff in parallel', (done) ->
      fsp.readdir temp .then (fs1) ->
        promise.pseq [ fsp.touch "#{temp}/x-#{n}" for n from 1 to 10 ] .then ->
          fsp.readdir temp .then (fs2) ->
            promise.pseq [ fsp.unlink "#{temp}/x-#{n}" for n from 1 to 10 ] .then ->
              fsp.readdir temp .then (fs3) ->
                [ l1, l2, l3 ] = [ fs1.length, fs2.length, fs3.length ]
                if l1 is l3 and l2 is l1 + 10 then done!
                else done [ fs1, fs2, fs3 ]
      .on-error -> done new Error it

