
# A Promise represents an on-going background computation.
#
# It's a state-machine that starts in its "waiting" state and can move from
# there into being "fulfilled" or "broken". Once fulfilled or broken, it stays
# that way.
#
# Callbacks can be notified of the state transition. A late-registered callback
# will still be notified if the state it is listening to is already achieved.
#
# There is no guarantee of the (a-)synchronicity of callback invocation wrt
# registration.
#
class Promise

  (init) ->
    @complete init if init?

  # Hook a listener. It is invoked only once, if the state targeted is
  # eventually echieved, or zero times otherwise.
  #
  on-completed: (cb) -> @_on-event \succ, (@[]_onsucc), cb
  on-error    : (cb) -> @_on-event \err , (@[]_onerr ), cb

  _on-event: (tag, queue, cb) ->
    switch @_done
      case void => queue.push cb
      case tag  => cb @_x
    @

  # Make the transition, if the promise is new.
  #
  complete: !(value) -> @_finalize \succ, @_onsucc, value
  reject  : !(error) -> @_finalize \err , @_onerr , error

  _finalize: !(tag, queue, value) ->
    unless @_done
      @_done = tag
      @_x    = value
      for cb in queue or [] then cb value
      @_onsucc = @_onerr = null

  # Combine a function of signature `(a) -> b` or `(a) -> Promise b` with a
  # promise of type `Promise a`, forming a new promise of type `Promise b`.
  #
  # The new promise is fulfilled with the result of the function applied to the
  # value of the promise if the function does not return a promise, or with the
  # result of the returned promise.
  #
  # It is broken if either the first or second promise is, or the function
  # throws.
  #
  # ( promise a .then f) == (f a)
  # ( p.then promise ) == p
  # ( p.then f1 .then f2 ) == ( p.then -> f1!then f2 )
  #   ( as long as f1 does not depend on p's result )
  # ( p.then (a) -> promise(f a) ) == ( p.then f )
  # 
  # This is a conflation of Haskell's `fmap` and `>>=` or Scala's `map` and
  # `flatMatmap`, specialized for promises.
  #
  then: (fn) ->
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

  # Combine a promise with a chain of further functions.
  # ( p.chain [f1, f2] ) == ( p.then f1 .then f2 ) == ( p.then -> f1!then f2 )
  #
  chain: (...fns) -> fns.reduce ((p, fn) -> p.then fn), @

  # Add a node-style callback -- wait for either event.
  #
  cb: (cb) ->
    @on-completed !(result) -> cb null, result
    @on-error     !(err)    -> cb err

  # Make a promise that fails after the given number of milliseconds, or
  # completes with the result of the original promise.
  #
  timeout: (ms) ->
    @then ((x) -> x) |> tap !(p) ->
      set-timeout (-> p.reject \timeout), ms

tap = (fn, x) --> fn.call @, x ; x

module.exports = promise = (-> new Promise it)

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

  ..wrap = (x) ->
    case x instanceof Promise => x
    case _                    => promise x

  # Convert an array or promises into a promise of array.
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

  # Wait for an array or promises to complete.
  #
  # ( seq arr .then -> f! ) == ( seq_ arr .then f )
  #
  ..seq_ = (parr) ->
    case not parr[0] => promise \seq
    case _           =>
      [ res, n ] = [ promise!, parr.length ]
      for p in parr then p
        ..on-completed -> res.complete \seq if --n is 0
        ..on-error     -> res.reject it
      res

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

    Object.create o |> tap !->
      for k, v of o when typeof! v is \Function and cond k
        it[k] = promise.fwrap v

  # Construct a promise that will complete after the given number of
  # milliseconds.
  #
  ..after = (ms) ->
    promise! |> tap !(p) ->
      set-timeout (-> p.complete new Date), ms

