import asynchttpserver
import asyncdispatch
import phoon/[context, response]
import phoon/routing/[errors, route, router, tree]
import options


type
    App* = ref object
        router: Router
        routing_table: Tree[Route]
        bad_request_callback*: Callback

proc default_bad_request_callback(context: Context) {.async.} =
    context.BadRequest()


proc new*(app_type: type[App]): App =
    return App(
        router: Router(),
        routing_table: new Tree[Route],
        bad_request_callback: default_bad_request_callback
    )


proc head*(self: var App, path: string, callback: Callback) =
    self.router.head(path, callback)


proc delete*(self: var App, path: string, callback: Callback) =
    self.router.delete(path, callback)


proc get*(self: var App, path: string, callback: Callback) =
    self.router.get(path, callback)


proc options*(self: var App, path: string, callback: Callback) =
    self.router.options(path, callback)


proc patch*(self: var App, path: string, callback: Callback) =
    self.router.patch(path, callback)


proc post*(self: var App, path: string, callback: Callback) =
    self.router.post(path, callback)


proc put*(self: var App, path: string, callback: Callback) =
    self.router.put(path, callback)


proc mount*(self: var App, path: string, router: Router) =
    self.router.mount(path, router)


proc bad_request*(self: var App, callback: Callback) =
    self.bad_request_callback = callback


proc compile_routes*(self: var App) =
    let middlewares = self.router.get_middlewares()

    for path, route in self.router.get_route_pairs():
        var compile_route = route.apply(middlewares)
        self.routing_table.insert(path, compile_route)


proc dispatch*(self: App, context: Context): Future[Response] {.async.} =
    let path = context.request.url.path

    let potential_match = self.routing_table.match(path)
    if potential_match.isNone:
        return response.NotFound()

    let match = potential_match.get()
    let route = match.value
    let callback = route.get_callback_of(context.request.reqMethod)
    if callback.isNone:
        return response.MethodNotAllowed()

    context.parameters = match.parameters
    {.gcsafe.}:
        let future = callback.get()(context)
        yield future
        if future.failed:
            await self.bad_request_callback(context)
            return context.response
        else:
            return context.response


proc use*(self: App, middleware: Middleware) =
    self.router.use(middleware)


proc serve*(self: App, port: int) =
    var app = deepCopy(self)
    app.compile_routes()

    proc main_dispatch(request: Request) {.async, gcsafe.} =
        var context = Context(request: request)
        let response = await app.dispatch(context)
        await request.respond(response.status_code, response.body)

    let server = newAsyncHttpServer()
    waitFor server.serve(Port(port), main_dispatch)


proc serve*(self: App) =
    self.serve(8080)

export asynchttpserver
export asyncdispatch
export context
export errors
export route
export router
export tree
