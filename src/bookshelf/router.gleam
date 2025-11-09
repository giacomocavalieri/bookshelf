import bookshelf/book.{type Book, Book, ToRead}
import bookshelf/page
import bookshelf/web
import filepath
import gleam/dict
import gleam/http
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/calendar.{type Date}
import gleam/time/timestamp
import lustre/element
import simplifile
import storail
import wisp.{type FormData, type Request, type Response}

pub fn handle_request(context: web.Context, req: Request) -> Response {
  use req <- web.middleware(context, req)
  case req.method, wisp.path_segments(req) {
    // The homepage displaying a compact list of all my books.
    http.Get, [] -> {
      let assert Ok(books) = storail.read_namespace(context.db, [])

      dict.values(books)
      |> list.sort(book.compare)
      |> page.home
      |> wisp.html_response(200)
    }

    http.Get, ["book", "new"] ->
      page.new_book_slot_form()
      |> element.to_string
      |> wisp.html_response(200)

    http.Post, ["book"] -> {
      use form <- wisp.require_form(req)
      case book_data(form) {
        Error(_) -> wisp.bad_request("invalid data")
        Ok(book_data) ->
          case upload_new_book(context, book_data) {
            Ok(book) ->
              page.book_list_item(book)
              |> element.to_string
              |> wisp.html_response(200)

            Error(DuplicateBook) -> wisp.response(409)
            Error(_) -> wisp.internal_server_error()
          }
      }
    }

    http.Delete, ["book", isbn] -> {
      let assert Ok(_) = delete_book(context, isbn)
      wisp.redirect("/")
    }

    http.Patch, ["book", isbn, ..remaining_path] ->
      handle_book_patch_request(context, req, isbn, remaining_path)

    _, _ -> wisp.not_found()
  }
}

/// Book patch requests are triggered by htmz targets, so they will return
/// html fragments as responses, appropriate to replace the target in the detail
/// page.
///
fn handle_book_patch_request(
  context: web.Context,
  req: Request,
  isbn: String,
  remaining_path: List(String),
) -> Response {
  case remaining_path {
    ["rating"] -> {
      let rating =
        wisp.get_query(req)
        |> list.key_find("value")
        |> result.try(int.parse)

      case rating {
        Error(_) -> wisp.bad_request("invalid rating")
        Ok(rating) ->
          update_and_write_book(context.db, isbn, book.rate(_, rating))
          |> updated_book_status_response
      }
    }

    ["cover"] -> {
      use form <- wisp.require_form(req)
      case list.key_find(form.files, "cover") {
        Error(_) -> wisp.bad_request("no cover")
        Ok(cover) -> {
          let assert Ok(cover_file_name) = save_cover(context, isbn, cover)
          let result =
            update_and_write_book(context.db, isbn, fn(book) {
              Ok(book.set_cover(book, cover_file_name))
            })

          case result {
            Error(storail.ObjectNotFound(_, _)) -> wisp.not_found()
            Error(_) -> wisp.internal_server_error()

            Ok(book) ->
              page.book_cover(book)
              |> element.to_string
              |> wisp.html_response(200)
          }
        }
      }
    }

    ["started"] ->
      update_and_write_book(context.db, isbn, book.start(_, today()))
      |> updated_book_status_response

    ["finished"] ->
      update_and_write_book(context.db, isbn, book.finish(_, today()))
      |> updated_book_status_response

    ["dropped"] ->
      update_and_write_book(context.db, isbn, book.drop(_, today()))
      |> updated_book_status_response

    _ -> wisp.not_found()
  }
}

fn save_cover(
  context: web.Context,
  isbn: String,
  cover: wisp.UploadedFile,
) -> Result(String, simplifile.FileError) {
  let extension =
    filepath.extension(cover.file_name)
    |> result.map(fn(extension) { "." <> extension })
    |> result.unwrap("")

  use _nil <- result.try(
    context.storage_directory
    |> filepath.join("covers")
    |> simplifile.create_directory_all(),
  )

  let cover_file_name = isbn <> extension

  context.storage_directory
  |> filepath.join("covers")
  |> filepath.join(cover_file_name)
  |> simplifile.copy_file(cover.path, to: _)
  |> result.replace(cover_file_name)
}

/// Returns today's date, using the machine's local offset.
///
fn today() -> Date {
  let #(date, _time) =
    timestamp.system_time()
    |> timestamp.to_calendar(calendar.local_offset())

  date
}

// BOOK CREATION FORM ----------------------------------------------------------

type BookData {
  BookData(cover: Option(wisp.UploadedFile), isbn: String, title: String)
}

fn book_data(form: FormData) -> Result(BookData, Nil) {
  case form.values {
    [#("isbn", isbn), #("title", title)] -> {
      let cover = case form.files {
        [#("cover", wisp.UploadedFile(file_name: "", path: _))] -> None
        [#("cover", cover)] -> Some(cover)
        _ -> None
      }
      Ok(BookData(isbn:, cover:, title:))
    }

    _ -> Error(Nil)
  }
}

type UploadError {
  DbError(storail.StorailError)
  CoverError(simplifile.FileError)
  DuplicateBook
}

/// Updates a book with the given function that may or may not update it.
/// It returns the new value for the book (the book is unchanged if the update
/// function doesn't produce an updated version) or an error if the new version
/// of the book couldn't be saved to the store.
///
fn upload_new_book(
  context: web.Context,
  book_data: BookData,
) -> Result(Book, UploadError) {
  let BookData(cover:, isbn:, title:) = book_data

  let key = storail.key(context.db, isbn)
  use existing_book <- result.try(
    storail.optional_read(key)
    |> result.map_error(DbError),
  )

  use cover <- result.try(case cover {
    None -> Ok(None)
    Some(cover) ->
      save_cover(context, book_data.isbn, cover)
      |> result.map(Some)
      |> result.map_error(CoverError)
  })

  case existing_book {
    Some(_) -> Error(DuplicateBook)
    None -> {
      let book = Book(title:, isbn:, cover:, status: ToRead, genres: [])
      storail.write(key, book)
      |> result.map_error(DbError)
      |> result.replace(book)
    }
  }
}

// UPDATING BOOK ---------------------------------------------------------------

/// Updates a book with the given function that may or may not update it.
/// It returns the new value for the book (the book is unchanged if the update
/// function doesn't produce an updated version) or an error if the new version
/// of the book couldn't be saved to the store.
///
fn update_and_write_book(
  db: storail.Collection(Book),
  isbn: String,
  update: fn(Book) -> Result(Book, Nil),
) -> Result(Book, storail.StorailError) {
  let key = storail.key(db, isbn)
  use book <- result.try(storail.read(key))

  case update(book) {
    Error(_) -> Ok(book)
    // We only write the new version of the book if nothing has changed!
    Ok(updated_book) if updated_book == book -> Ok(book)
    Ok(updated_book) ->
      storail.write(key, updated_book)
      |> result.replace(updated_book)
  }
}

/// Given the outcome of updating and storing the new book, this returns an
/// html fragment to be used by htmz to replace the book status in an
/// interactive page.
///
fn updated_book_status_response(
  outcome: Result(Book, storail.StorailError),
) -> Response {
  case outcome {
    Error(storail.ObjectNotFound(_, _)) -> wisp.not_found()
    Error(_) -> wisp.internal_server_error()

    Ok(book) ->
      page.book_details(book)
      |> element.to_string
      |> wisp.html_response(200)
  }
}

// DELETING BOOKS --------------------------------------------------------------
//

type DeleteBookError {
  DeleteDbError(storail.StorailError)
  DeleteCoverError(simplifile.FileError)
}

fn delete_book(
  context: web.Context,
  isbn: String,
) -> Result(Nil, DeleteBookError) {
  let key = storail.key(context.db, isbn)
  use book <- result.try(storail.read(key) |> result.map_error(DeleteDbError))
  use _ <- result.try(case book.cover {
    None -> Ok(Nil)
    Some(cover) ->
      context.storage_directory
      |> filepath.join("covers")
      |> filepath.join(cover)
      |> simplifile.delete
      |> result.map_error(DeleteCoverError)
  })

  storail.delete(key)
  |> result.map_error(DeleteDbError)
}
