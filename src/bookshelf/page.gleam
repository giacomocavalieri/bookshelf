import bookshelf/book.{type Book}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/calendar.{
  type Date, type Month, April, August, December, February, January, July, June,
  March, May, November, October, September,
}
import lustre/attribute.{attribute}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg

pub fn home(books: List(Book)) -> String {
  element.fragment([
    html.header([attribute.class("bookshelf-header")], [
      html.h1([], [html.text("I miei libri")]),
      html.a(
        [
          attribute.class("add-book-button"),
          attribute.target("htmz"),
          attribute.href("/book/new#new-book-slot"),
        ],
        [html.text(" +")],
      ),
    ]),
    html.main([], [
      book_list(books),
    ]),
  ])
  |> layout
}

fn book_list(books: List(Book)) -> Element(msg) {
  html.ul([attribute.class("books-list")], [
    new_book_slot_target(),
    ..list.map(books, book_list_item)
  ])
}

pub fn book_list_item(book: Book) -> Element(msg) {
  html.li([attribute.class("book")], [
    book_cover(book),
    book_details(book),
  ])
}

fn new_book_slot_target() {
  html.div([attribute.id("new-book-slot")], [])
}

pub fn new_book_slot_form() {
  element.fragment([
    new_book_slot_target(),
    html.li([attribute.id("new-book-item")], [
      html.form(
        [
          attribute.class("book"),
          attribute.method("POST"),
          attribute.action("book#new-book-item"),
          attribute.target("htmz"),
          attribute.enctype("multipart/form-data"),
        ],
        [
          html.div([attribute.class("missing-book-cover")], [
            cover_input(NoAutoSubmit),
          ]),
          html.div([attribute.class("book-details")], [
            html.div([attribute.class("book-header")], [
              html.input([
                attribute.class("book-input book-title"),
                attribute.name("title"),
                attribute.spellcheck(False),
                attribute.required(True),
                attribute.pattern("[\\S\\s]+[\\S]+"),
                attribute.aria_label("A non empty title"),
                attribute.placeholder("Titolo"),
              ]),
            ]),
            html.div([attribute.class("book-status")], [
              html.input([
                attribute.required(True),
                attribute.spellcheck(False),
                attribute.name("isbn"),
                attribute.inputmode("numeric"),
                attribute.class("book-input"),
                attribute.pattern("[0-9]+"),
                attribute.aria_label("An ISBN with no dashes nor spaces"),
                attribute.placeholder("ISBN"),
              ]),
              html.button(
                [attribute.type_("submit"), attribute.class("update-button")],
                [html.text("Aggiungi")],
              ),
            ]),
          ]),
        ],
      ),
    ]),
  ])
}

pub fn book_cover(book: Book) -> Element(msg) {
  case book.cover {
    None ->
      html.form(
        [
          attribute.id("book-cover-" <> book.isbn),
          attribute.class("missing-book-cover"),
          attribute.method("POST"),
          attribute.target("htmz"),
          attribute.enctype("multipart/form-data"),
          attribute.action(
            "/book/"
            <> book.isbn
            <> "/cover?_method=PATCH#book-cover-"
            <> book.isbn,
          ),
        ],
        [cover_input(SubmitOnChange)],
      )

    Some(cover) ->
      html.img([
        attribute.id("book-cover-" <> book.isbn),
        attribute.class("book-cover"),
        attribute.src("/cover/" <> cover),
        attribute.alt("cover image for " <> book.title),
      ])
  }
}

type CoverSubmit {
  SubmitOnChange
  NoAutoSubmit
}

fn cover_input(submit: CoverSubmit) -> Element(msg) {
  html.label([], [
    html.text("?"),
    html.input([
      attribute.type_("file"),
      attribute.name("cover"),
      case submit {
        SubmitOnChange -> attribute("onchange", "form.submit()")
        NoAutoSubmit -> attribute.none()
      },
      attribute.accept(["image/*"]),
    ]),
  ])
}

pub fn book_details(book: Book) -> Element(msg) {
  html.div(
    [
      attribute.id("book-details-" <> book.isbn),
      attribute.class("book-details"),
    ],
    [
      html.div([attribute.class("book-header")], [
        html.div([attribute.class("book-title")], [
          html.h2([], [html.text(book.title <> " ")]),
          delete_form(book),
        ]),
        rate_form(book),
      ]),
      book_status(book),
    ],
  )
}

fn delete_form(book: Book) -> Element(msg) {
  html.form(
    [
      attribute.action("/book/" <> book.isbn <> "?_method=DELETE"),
      attribute.method("POST"),
      attribute(
        "onsubmit",
        "return confirm(\"Sicuro di voler eliminare il libro?\")",
      ),
    ],
    [
      html.button([attribute.class("delete-book-button")], [
        html.text("X"),
      ]),
    ],
  )
}

fn rate_form(book: Book) -> Element(msg) {
  case book.status {
    book.Dropped(..) | book.Reading(..) | book.ToRead -> element.none()
    book.Read(rating:, ..) -> {
      let rating_button = fn(index) {
        let attributes = [
          attribute.class("star-button"),
          attribute.type_("submit"),
          attribute.formaction(
            "/book/"
            <> book.isbn
            <> "/rating?_method=PATCH&value="
            <> int.to_string(index)
            <> "#book-details-"
            <> book.isbn,
          ),
        ]

        html.button(attributes, [
          case index <= rating {
            True -> html.text("★")
            False -> html.text("☆")
          },
        ])
      }

      let attributes = [
        attribute.method("POST"),
        attribute.target("htmz"),
        attribute.class("rate-form"),
      ]

      html.form(attributes, [
        rating_button(1),
        rating_button(2),
        rating_button(3),
        rating_button(4),
        rating_button(5),
      ])
    }
  }
}

pub fn book_status(book: Book) -> Element(msg) {
  html.div([attribute.class("book-status")], [
    case book.status {
      book.Read(rating: _, start_date:, end_date:) ->
        read_status(start_date, end_date)
      book.ToRead -> to_read_status(book.isbn)
      book.Reading(start_date:) -> reading_status(book.isbn, start_date)
      book.Dropped(start_date:, drop_date:) ->
        dropped_status(start_date, drop_date)
    },
  ])
}

fn read_status(start_date: Date, end_date: Date) -> Element(msg) {
  html.p([], [
    html.text(date_to_string(start_date)),
    html.br([]),
    html.text(date_to_string(end_date)),
  ])
}

fn to_read_status(isbn: String) -> Element(msg) {
  html.form(
    [
      attribute.method("POST"),
      attribute.target("htmz"),
      attribute.action(
        "/book/" <> isbn <> "/started?_method=PATCH#book-details-" <> isbn,
      ),
    ],
    [
      html.button(
        [attribute.type_("submit"), attribute.class("update-button")],
        [html.text("Inizia a leggere")],
      ),
    ],
  )
}

fn reading_status(isbn: String, start_date: Date) -> Element(msg) {
  element.fragment([
    html.p([], [
      html.text(date_to_string(start_date)),
      html.br([]),
      html.text("in lettura"),
    ]),
    html.form(
      [
        attribute.method("POST"),
        attribute.target("htmz"),
        attribute.action(
          "/book/" <> isbn <> "/finished?_method=PATCH#book-details-" <> isbn,
        ),
      ],
      [
        html.button(
          [
            attribute.type_("submit"),
            attribute.class("update-button"),
          ],
          [html.text("Ho finito il libro")],
        ),
      ],
    ),
  ])
}

fn dropped_status(start_date: Date, _drop_date: Date) -> Element(msg) {
  html.text(date_to_string(start_date) <> " - abbandonato")
}

fn date_to_string(date: Date) {
  let calendar.Date(year:, month:, day:) = date

  string.pad_start(int.to_string(day), to: 2, with: "0")
  <> " "
  <> month_to_string(month)
  <> " "
  <> string.pad_start(int.to_string(year), to: 4, with: "0")
}

fn month_to_string(month: Month) -> String {
  case month {
    January -> "gennaio"
    February -> "febbraio"
    March -> "marzo"
    April -> "aprile"
    May -> "maggio"
    June -> "giugno"
    July -> "luglio"
    August -> "agosto"
    September -> "settembre"
    October -> "ottobre"
    November -> "novembre"
    December -> "dicembre"
  }
}

fn layout(element: Element(msg)) -> String {
  element.fragment([
    html.title([], "Bookshelf"),
    html.meta([attribute.charset("utf-8")]),
    html.meta([attribute.lang("it")]),
    html.meta([
      attribute.name("viewport"),
      attribute.content("width=device-width, initial-scale=1"),
    ]),
    html.head([], [
      html.link([
        attribute.href("/static/styles/reset.css"),
        attribute.rel("stylesheet"),
      ]),
      html.link([
        attribute.href("/static/styles/styles.css"),
        attribute.rel("stylesheet"),
      ]),
      html.script([attribute.src("/static/js/htmz.js")], ""),
    ]),
    html.body([], [
      element,
      // The htmz iframe to dinamically replace pieces of the page with html
      // that is sent back from the server.
      html.iframe([
        attribute.hidden(True),
        attribute.name("htmz"),
        attribute("onload", "window.htmz(this)"),
      ]),

      // The svg filter used to apply the duotone effect.
      duotone_filter(),
    ]),
  ])
  |> element.to_document_string
}

fn duotone_filter() -> Element(msg) {
  let grayscale_matrix =
    svg.fe_color_matrix([
      attribute("result", "grayscale"),
      attribute.type_("matrix"),
      attribute(
        "values",
        "1 0 0 0 0
         1 0 0 0 0
         1 0 0 0 0
         0 0 0 1 0",
      ),
    ])

  let duotone_light_filter =
    element.element(
      "feComponentTransfer",
      [
        attribute("result", "duotone"),
        attribute("color-interpolation-filters", "sRGB"),
      ],
      [
        svg.fe_func_r([
          attribute.type_("table"),
          attribute("tableValues", "0.219 0.722"),
        ]),
        svg.fe_func_g([
          attribute.type_("table"),
          attribute("tableValues", "0.169 0.761"),
        ]),
        svg.fe_func_b([
          attribute.type_("table"),
          attribute("tableValues", "0.149 0.725"),
        ]),
        svg.fe_func_a([
          attribute.type_("table"),
          attribute("tableValues", "0 1"),
        ]),
      ],
    )

  let duotone_dark_filter =
    element.element(
      "feComponentTransfer",
      [
        attribute("result", "duotone"),
        attribute("color-interpolation-filters", "sRGB"),
      ],
      [
        svg.fe_func_r([
          attribute.type_("table"),
          attribute("tableValues", "0.722 0.219"),
        ]),
        svg.fe_func_g([
          attribute.type_("table"),
          attribute("tableValues", "0.761 0.169"),
        ]),
        svg.fe_func_b([
          attribute.type_("table"),
          attribute("tableValues", "0.725 0.149"),
        ]),
        svg.fe_func_a([
          attribute.type_("table"),
          attribute("tableValues", "0 1"),
        ]),
      ],
    )

  svg.svg([], [
    svg.filter([attribute.id("duotone-light")], [
      grayscale_matrix,
      duotone_light_filter,
    ]),
    svg.filter([attribute.id("duotone-dark")], [
      grayscale_matrix,
      duotone_dark_filter,
    ]),
  ])
}
