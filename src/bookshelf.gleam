import bookshelf/book
import bookshelf/router
import bookshelf/web
import filepath
import gleam/erlang/process
import mist
import storail
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(priv_directory) = wisp.priv_directory("bookshelf")
  let static_directory = filepath.join(priv_directory, "static")
  let storage_directory = filepath.join(priv_directory, "storage")

  let context =
    web.Context(
      static_directory:,
      storage_directory:,
      db: storail.Collection(
        name: "books",
        to_json: book.to_json,
        decoder: book.decoder(),
        config: storail.Config(storage_path: storage_directory),
      ),
    )

  let assert Ok(_) =
    router.handle_request(context, _)
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(8000)
    |> mist.bind("0.0.0.0")
    |> mist.start

  process.sleep_forever()
}
