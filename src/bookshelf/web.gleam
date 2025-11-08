import bookshelf/book.{type Book}
import filepath
import storail
import wisp

pub type Context {
  Context(
    storage_directory: String,
    static_directory: String,
    db: storail.Collection(Book),
  )
}

pub fn middleware(
  context: Context,
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use req <- wisp.csrf_known_header_protection(req)

  use <- wisp.serve_static(
    req,
    under: "/cover",
    from: context.storage_directory
      |> filepath.join("covers"),
  )

  use <- wisp.serve_static(
    req,
    under: "/static",
    from: context.static_directory,
  )

  handle_request(req)
}
