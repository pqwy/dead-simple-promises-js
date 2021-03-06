# A Promise represents an on-going background computation.
#
# It's a state-machine that starts in its "pending" state and can move from
# there into being "fulfilled" or "rejected". When fulfilled or rejected, it
# stays that way.
#
# Callbacks can be notified of the state transition. A late-registered callback
# will still be notified if the state it is listening to is already achieved.
#
# There is no guarantee of the (a-)synchronicity of callback invocation wrt
# registration.
#
#
# Design notes:
#
# * The promise is described with an object instead of a closure. This is a bit
# ugly and certainly doesn't help information hiding, but has a large,
# measurable impact on v8 because of it's (current) optimization bias against
# closures.
#
# * `then` doesn't trampoline because doing so kills almost an order of
# magnitude of speed, defeating the purpose of having a promise that can be used
# for *everything*. This does neccessitate keeping track of stack-nesting on
# usage, though.
#
# * `then` creates a promise. It is unclear if it is wise to allow capturing the
# error reason into a function - if the error handler returns a promise, should
# that promise be waited on? if so, is its success then the new _error_ of the
# combined promise, or does it save the execution? Since the semantics is
# unclear, installing the error handler does not create a new promise - the
# handler is simply called. And because of this, `then` does not accept one.
#
# * The promise is its own deferrable. I see no real point in keeping them
# separate.
#
# * Some functions are repetitive since abstracting away the common code has a
# noticable performance impact.
#
#
class Promise

  # A promise can be constructed as already fulfilled.
  #
  (init) ->
    @complete init if init isnt void

  # Hook a listener. It is invoked only once, if the state targeted is
  # eventually echieved, or zero times otherwise.
  #
  on-completed : (cb) ->
    switch @_done
      case void  => @[]_onsucc.push cb
      case \succ => cb @_x
    @

  on-error : (cb) ->
    switch @_done
      case void => @[]_onerr.push cb
      case \err => @_handled = true ; cb @_x
    @

  # Make the transition, if the promise is pending.
  #
  complete : !(value) ->
    unless @_done
      @_done = \succ
      @_x    = value
      for cb in @[]_onsucc then cb value
      @_onsucc = @_onerr = null

  reject : !(error) ->
    unless @_done
      @_done = \err
      @_x    = error
      for cb in @[]_onerr then cb error
      else if @@catch_them_all
        exn = new Error "unhandled rejection: #{err-to-string error}"
          ..reason = error
        le-next-tick ~>
          unless @_handled then throw exn
      @_onsucc = @_onerr = null

  # Raise an error if there were no error handlers.
  #
  @@catch_them_all = true

  # Combine a function of signature `(a) -> b` or `(a) -> Promise b` with a
  # promise of type `Promise a`, forming a new promise of type `Promise b`.
  #
  # The new promise is fulfilled with the result of the function applied to the
  # value of the promise if the function does not return a promise, or with the
  # result of the returned promise.
  #
  # It is rejected if either the first or second promise is, or the function
  # throws.
  #
  # ( promise a .then f ) == | (f a)         , if f returns a promise
  #                          | promise (f a) , otherwise
  #   - in both cases any exceptions thrown by f are converted into promise
  #     failure
  #
  # ( p.then promise ) == p
  #
  # ( p.then f1 .then f2 ) == ( p.then -> f1!then f2 )
  #   - as long as f1 does not depend on p's result
  #
  # ( p.then (a) -> promise(f a) ) == ( p.then f )
  # 
  # This is a conflation of Haskell's `fmap` and `>>=` or Scala's `map` and
  # `flatMatmap`, specialized for promises.
  #
  then : (fn) ->
    p = new Promise
    @on-completed !(result) ->
      try
        if ( x = fn result ) instanceof Promise
          x.on-completed !(result) -> p.complete result
           .on-error     !(err)    -> p.reject err
        else p.complete x
      catch e => p.reject e
    @on-error !(err) -> p.reject err
    p

  # Much like #then, but for failure:
  #
  # ( p.else _ ) == p
  #  - if p completes with success
  #
  # ( p.else f ) == ( promise(err).then f )
  #  - if p fails with err
  #
  else : (fn) ->
    p = new Promise
    @on-completed !(result) -> p.complete result
    @on-error !(err) ->
      new Promise err .then fn
        .then     -> p.complete it
        .on-error -> p.reject it
    p

  to-string : -> "<Promise [#{@_done or \pending}]>"
  inspect   : -> @to-string!

  ## various goodies ##

  # Combine a promise with a chain of further functions.
  #
  # ( p.thread [f1, f2] ) == ( p.then f1 .then f2 ) == ( p.then -> f1!then f2 )
  #
  thread : (...fns) -> fns.reduce ((p, fn) -> p.then fn), @

  # Add a node-style callback -- wait for either event.
  #
  cb : !(cb) ->
    @on-completed !(result) -> cb null, result
    @on-error     !(err)    -> cb err

  # Create an object whose `then` is Promises/A+ compatible.
  # (Almost. Giving defined-but-non-function callbacks will error out.)
  #
  to-aplus : ->
    then : (succ = id, fail = id) !~>
      le-next-tick !~> @then succ .on-error fail

  # Strictly asynchronous `then`, à la A+.
  #
  then-later : (fn) -> le-next-tick ~> @then fn

  # Make a promise that fails after the given number of milliseconds, or
  # completes with the result of the original promise.
  #
  timeout : (ms) ->
    p = @then ((x) -> x)
    set-timeout (-> p.reject \timeout), ms
    p

# Main export is a factory.
#
module.exports = promise = (-> new Promise it)

  # Control whether all errors must have handlers, or can be silently ignored.
  #
  # Defaults to true.
  #
  ..strict-errors = -> Promise.catch_them_all = it

  # Create a promise that errors out.
  #
  ..error = (err) -> promise!
    ..reject err

  # The common idiom of creating a promise, firing up a function to
  # complete/reject it and returning the promise.
  #
  ..create = (initfun) ->
    p = promise!
    initfun (-> p.complete it), (-> p.reject it)
    p

  # Type predicate.
  #
  ..is = -> it instanceof Promise

  # Convert a function that takes a node-style callback as the last argument
  # into a function with one less argument that returns a promise.
  #
  ..fwrap = (fun) -> (...xs) ->
    p = promise!
    try
      fun.apply @, xs.concat [ (err, res) ->
        case err => p.reject err
        case _   => p.complete res
      ]
    catch e => p.reject e
    p

  # Transform a value into a promise, it it's not a promise already.
  #
  ..wrap = (x) ->
    case x instanceof Promise => x
    case x is void            => promise null
    case _                    => promise x

  # Convert an array of promises into a promise of array.
  # 
  # ( seq [promise(a), promise(b), ...] ) == ( promise [a, b, ...] )
  #
  ..seq = (parr) ->
    case not parr[0] => promise []
    case _           =>
      [ arr, res, n ] = [ [], promise!, parr.length ]
      for p, i in parr
        do (slot = i) -> p
          ..on-completed (x) ->
            arr[slot] = x
            res.complete arr if --n is 0
          ..on-error (err) -> res.reject err
      res

  # Wait for an array of promises to complete.
  #
  # ( seq arr .then -> f null ) == ( seq_ arr .then f )
  #
  ..seq_ = (parr) ->
    case not parr[0] => promise null
    case _           =>
      [ res, n ] = [ promise!, parr.length ]
      for p in parr then p
        ..on-completed -> res.complete null if --n is 0
        ..on-error     -> res.reject it
      res

  # Chain a sequence of delayed promises.
  #
  # ( thread [f0, f1, f2] ) == ( f0!then f1 .then f2 ) == ( f0!then -> f1!then f2 )
  #
  ..thread = (f0, ...fs) -> promise.wrap f0! .thread ...fs

  # Apply a "regular" function onto promises, yielding a promise of the result.
  #
  ..lift = (f, ...ps) ->
    promise.seq (ps.map promise.wrap) .then (xs) -> f ...xs

  # Take an object and a predicate and return another object with all the
  # function-valued members of the original one `fwrap`-ped, if their names
  # satisfy the predicate. The predicate is either a function or a regex.
  #
  ..owrap = (o, pred = /^[^_]/) ->

    cond =
      switch typeof! pred
        case \Function => pred
        case \RegExp   => -> it.match pred
        case _         => throw new Error "owrap: bad predicate: #pred"

    ( Object.create o ) <<<
      {[k, promise.fwrap v] for k, v of o
          when typeof! v is \Function and cond k}

  # Promise that completes after `ms` milliseconds.
  #
  ..after = (ms) ->
    p = promise!
    set-timeout (-> p.complete new Date), ms
    p

  # Promise that completes in node's `process.next-tick`.
  #
  ..next-tick = (x) ->
    p = promise!
    process.next-tick -> p.complete x
    p

  # Promise that completes in node's setImmediate.
  #
  ..set-immediate = (x) ->
    p = promise!
    set-immediate -> p.complete x
    p

  # Lift a Promise/A+-style promise into our flavour.
  #
  ..from-aplus = (ap) ->
    p = promise!
    ap.then (-> p.complete it), (-> p.reject it)
    p

id = (x) -> x

le-next-tick = do ->
  case set-immediate?      => set-immediate
  case process?.next-tick? => process.next-tick
  case _                   => (cb) -> set-timeout cb, 0

err-to-string = (x) ->
  case x.stack? => x.to-string!
  case _        => JSON.stringify x
