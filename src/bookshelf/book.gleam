import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option, Some}
import gleam/order.{type Order}
import gleam/string
import gleam/time/calendar.{type Date, type Month, October}

pub type Book {
  Book(
    title: String,
    isbn: String,
    cover: Option(String),
    status: Status,
    genres: List(Genre),
  )
}

pub type Status {
  ToRead
  Reading(start_date: Date)
  Dropped(start_date: Date, drop_date: Date)
  Read(start_date: Date, end_date: Date, rating: Int)
}

pub type Genre {
  ScienceFiction
  Horror
  Fantasy
  Fiction
  Gothic
}

pub fn genre_to_string(genre: Genre) -> String {
  case genre {
    ScienceFiction -> "science fiction"
    Horror -> "horror"
    Fantasy -> "fantasy"
    Fiction -> "fiction"
    Gothic -> "gothic"
  }
}

// UPDATING A BOOK -------------------------------------------------------------

pub fn start(book: Book, start_date: Date) -> Result(Book, Nil) {
  case book.status {
    ToRead -> Ok(Book(..book, status: Reading(start_date:)))
    Dropped(..) | Read(..) | Reading(..) -> Error(Nil)
  }
}

pub fn finish(book: Book, end_date: Date) -> Result(Book, Nil) {
  case book.status {
    Reading(start_date:) ->
      Ok(Book(..book, status: Read(start_date:, end_date:, rating: 0)))
    ToRead | Dropped(..) | Read(..) -> Error(Nil)
  }
}

pub fn rate(book: Book, rating: Int) -> Result(Book, Nil) {
  case book.status {
    Read(..) as status -> Ok(Book(..book, status: Read(..status, rating:)))
    Dropped(..) | Reading(..) | ToRead -> Error(Nil)
  }
}

pub fn set_cover(book: Book, cover: String) -> Book {
  Book(..book, cover: Some(cover))
}

pub fn drop(book: Book, drop_date) {
  case book.status {
    Reading(start_date:) ->
      Ok(Book(..book, status: Dropped(start_date:, drop_date:)))
    Dropped(..) | Read(..) | ToRead -> Error(Nil)
  }
}

// ENCODING AND DECODING -------------------------------------------------------

pub fn to_json(book: Book) -> Json {
  let Book(title:, isbn:, status:, genres:, cover:) = book
  json.object([
    #("title", json.string(title)),
    #("isbn", json.string(isbn)),
    #("status", status_to_json(status)),
    #("genres", json.array(genres, genre_to_json)),
    #("cover", json.nullable(cover, json.string)),
  ])
}

fn status_to_json(status: Status) -> Json {
  case status {
    ToRead ->
      json.object([
        #("type", json.string("to_read")),
      ])

    Read(start_date:, end_date:, rating:) ->
      json.object([
        #("type", json.string("read")),
        #("start_date", date_to_json(start_date)),
        #("end_date", date_to_json(end_date)),
        #("rating", json.int(rating)),
      ])

    Reading(start_date:) ->
      json.object([
        #("type", json.string("reading")),
        #("start_date", date_to_json(start_date)),
      ])

    Dropped(start_date:, drop_date:) ->
      json.object([
        #("type", json.string("dropped")),
        #("start_date", date_to_json(start_date)),
        #("drop_date", date_to_json(drop_date)),
      ])
  }
}

fn genre_to_json(genre: Genre) -> Json {
  case genre {
    ScienceFiction -> json.string("science_fiction")
    Horror -> json.string("horror")
    Fantasy -> json.string("fantasy")
    Fiction -> json.string("fiction")
    Gothic -> json.string("gothic")
  }
}

fn date_to_json(date: Date) -> Json {
  let calendar.Date(year:, month:, day:) = date
  json.object([
    #("year", json.int(year)),
    #("month", json.int(calendar.month_to_int(month))),
    #("day", json.int(day)),
  ])
}

pub fn decoder() -> Decoder(Book) {
  use title <- decode.field("title", decode.string)
  use isbn <- decode.field("isbn", decode.string)
  use status <- decode.field("status", status_decoder())
  use genres <- decode.field("genres", decode.list(genre_decoder()))
  use cover <- missing_or_nullable_field("cover", decode.string)
  decode.success(Book(title:, isbn:, status:, genres:, cover:))
}

fn missing_or_nullable_field(
  field: String,
  decoder: Decoder(a),
  then: fn(Option(a)) -> Decoder(b),
) -> Decoder(b) {
  decode.optional_field(field, option.None, decode.optional(decoder), then)
}

fn status_decoder() -> Decoder(Status) {
  use variant <- decode.field("type", decode.string)
  case variant {
    "to_read" -> decode.success(ToRead)
    "read" -> {
      use start_date <- decode.field("start_date", date_decoder())
      use end_date <- decode.field("end_date", date_decoder())
      use rating <- decode.field("rating", decode.int)
      decode.success(Read(start_date:, end_date:, rating:))
    }
    "reading" -> {
      use start_date <- decode.field("start_date", date_decoder())
      decode.success(Reading(start_date:))
    }
    "dropped" -> {
      use start_date <- decode.field("start_date", date_decoder())
      use drop_date <- decode.field("drop_date", date_decoder())
      decode.success(Dropped(start_date:, drop_date:))
    }
    _ -> decode.failure(ToRead, "Status")
  }
}

fn genre_decoder() -> Decoder(Genre) {
  use variant <- decode.then(decode.string)
  case variant {
    "science_fiction" -> decode.success(ScienceFiction)
    "horror" -> decode.success(Horror)
    "fantasy" -> decode.success(Fantasy)
    "fiction" -> decode.success(Fiction)
    "gothic" -> decode.success(Gothic)
    _ -> decode.failure(Horror, "Genre")
  }
}

fn date_decoder() -> Decoder(Date) {
  use year <- decode.field("year", decode.int)
  use month <- decode.field("month", month_decoder())
  use day <- decode.field("day", decode.int)
  decode.success(calendar.Date(year:, month:, day:))
}

fn month_decoder() -> Decoder(Month) {
  use month <- decode.then(decode.int)
  case calendar.month_from_int(month) {
    Error(_) -> decode.failure(October, "Month")
    Ok(month) -> decode.success(month)
  }
}

pub fn compare(one: Book, other: Book) -> Order {
  case one.status, other.status {
    // Books that I'm reading are always the smallest, so they end up first.
    Reading(start_date: one_start), Reading(start_date: other_start) ->
      naive_date_compare(one_start, other_start)
      |> order.break_tie(string.compare(one.title, other.title))
    Reading(..), _ -> order.Lt
    _, Reading(..) -> order.Gt

    // Then we list the books in our "to read" list.
    // Listing them alphabetically.
    ToRead, ToRead -> string.compare(one.title, other.title)
    ToRead, _ -> order.Lt
    _, ToRead -> order.Gt

    // Then the ones we've read. Putting the ones we've finished recently first.
    Read(end_date: one_end, ..), Read(end_date: other_end, ..) ->
      naive_date_compare(one_end, other_end)
      |> order.break_tie(string.compare(one.title, other.title))
    Read(..), _ -> order.Lt
    _, Read(..) -> order.Gt

    // And finally the ones we've dropped always end up last.
    Dropped(..), Dropped(..) -> string.compare(one.title, other.title)
  }
}

fn naive_date_compare(one: Date, other: Date) -> Order {
  use <- order.lazy_break_tie(int.compare(one.year, other.year))
  use <- order.lazy_break_tie(int.compare(
    calendar.month_to_int(one.month),
    calendar.month_to_int(other.month),
  ))
  int.compare(one.day, other.day)
}
