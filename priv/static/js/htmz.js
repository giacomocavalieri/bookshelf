function htmz(frame) {
  if (frame.contentWindow.location.href === "about:blank") return;

  setTimeout(() => {
    document
      .querySelector(frame.contentWindow.location.hash || null)
      ?.replaceWith(...frame.contentDocument.body.childNodes);

    // ---------------------------------8<-----------------------------------
    // This extension clears the iframe's history from the global history
    // by removing the iframe from the DOM (but immediately adding it back
    // for subsequent requests).
    frame.remove();
    document.body.appendChild(frame);
    // --------------------------------->8-----------------------------------
  });
}
