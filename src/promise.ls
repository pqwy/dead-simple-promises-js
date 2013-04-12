
# A Promise is a structure in one of three statest: new, fulfilled and broken.
#
# A new promise is moved into fulfilled (resp. broken) state by invoking
# `complete` (resp `reject`). Once in one of these two states, that state is
# unchangeable.
#
# Event listeners can be added to a promise to be notified of it being
# fullfilled or broken; each listener is invoked zero times, if it's waiting
# for the state the promise will not reach, or once, if it's waiting for the
# state the promise entered. The listener is invoked regardless of whether the
# state-change occurres before or after registration. On top of that, there is
# no guarantee whether the listener will be invoked synchronously or
# asynchronously with registration.
#
class Promise

  (init) ->
    @complete init if init?

  # Receive the value with which this promise if fulfilled (resp. broken).
  #
  on-completed: (cb) -> @_on-event \succ, (@_onsucc or= []), cb
  on-error    : (cb) -> @_on-event \err , (@_onerr  or= []), cb

  _on-event: (tag, queue, cb) ->
    switch @_done
      case void => queue.push cb
      case tag  => cb @_x
    @

  # Set the promise to the fulfilled (resp.  broken) state if it wasn't in one
  # of those already.
  #
  complete: !(value) -> @_finalize \succ, @_onsucc, value
  reject  : !(error) -> @_finalize \err , @_onerr , error

  _finalize: !(tag, queue, value) ->
    unless @_done
      @_done = tag
      @_x    = value
      for cb in (queue || []) then cb value
      @_onsucc = @_onerr = null

  # Combine a function of signatures `(a) -> b` or `(a) -> Promise b` with a
  # promise of type `Promise a`, forming a new promise of type `Promise b`.
  #
  # The new promise is fulfilled with the result of the function if the function
  # does not return a promise and the original promise was fulfilled, or it will
  # be fulfilled when the second promise is fulfilled if the function returns a
  # promise. It will be broken if any of the promises along the way are broken.
  # 
  # In short, this is a combination of Haskell's `fmap` and `>>=`, or Scala's
  # `map` and `flatMap`.
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
  # p.seq[f1, f2] == p.then(p1).then(p2) == p.then(p1.then(p2))
  #
  seq: (...fns) -> fns.reduce ((p, fn) -> p.then fn), @

  # Add a node-style callback to wait for any of the possible events.
  cb: (cb) ->
    @on-completed !(result) -> cb null, result
    @on-error     !(err)    -> cb err

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

  # Convert an array or promises into a promise of array, that is fulfilled as
  # soon as all the promises are, or broken as soon as the first promise is.
  #
  ..pseq = (parr) ->
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

  ..after = (ms) ->
    promise! |> tap !(p) ->
      set-timeout (-> p.complete (new Date)), ms
