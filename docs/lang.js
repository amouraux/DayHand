// Offers the privacy policy or the support page in the reader's language.
// A banner, never a redirect: moving someone off the page they asked for is
// worse than not helping. Dismissing it is remembered; if storage is blocked
// the banner simply comes back, which is harmless.
(function () {
  var script = document.currentScript;
  if (!script) return;
  var page = script.getAttribute("data-page");
  var root = new URL(".", script.src).href;

  // folder -> [message, link text, dismiss label]
  var T = {
    "de": ["Diese Seite gibt es auch auf Deutsch.", "Auf Deutsch lesen", "Schließen"],
    "es": ["Esta página también está disponible en español.", "Leer en español", "Cerrar"],
    "fr": ["Cette page existe aussi en français.", "Lire en français", "Fermer"],
    "it": ["Questa pagina è disponibile anche in italiano.", "Leggi in italiano", "Chiudi"],
    "nl": ["Deze pagina is ook beschikbaar in het Nederlands.", "Lees in het Nederlands", "Sluiten"],
    "pt-pt": ["Esta página também está disponível em português.", "Ler em português", "Fechar"],
    "pt-br": ["Esta página também está disponível em português.", "Ler em português", "Fechar"],
    "ja": ["このページは日本語でもご覧いただけます。", "日本語で読む", "閉じる"],
    "ko": ["이 페이지는 한국어로도 볼 수 있습니다.", "한국어로 보기", "닫기"],
    "sv": ["Den här sidan finns också på svenska.", "Läs på svenska", "Stäng"],
    "da": ["Denne side findes også på dansk.", "Læs på dansk", "Luk"],
    "nb": ["Denne siden finnes også på norsk.", "Les på norsk", "Lukk"],
    "fi": ["Tämä sivu on saatavilla myös suomeksi.", "Lue suomeksi", "Sulje"],
    "pl": ["Ta strona jest dostępna także po polsku.", "Czytaj po polsku", "Zamknij"]
  };

  // A browser language tag -> the folder that serves it, or "" for none.
  function folderFor(tag) {
    var t = String(tag).toLowerCase();
    var base = t.split("-")[0];
    if (base === "pt") return t === "pt-pt" ? "pt-pt" : "pt-br";
    if (base === "no" || base === "nn" || base === "nb") return "nb";
    return T[base] ? base : "";
  }

  var langs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
  var folder = "";
  for (var i = 0; i < langs.length; i++) {
    if (String(langs[i]).toLowerCase().split("-")[0] === "en") break; // English first: nothing to offer
    folder = folderFor(langs[i]);
    if (folder) break;
  }
  if (!folder) return;

  try { if (localStorage.getItem("dh-lang-dismissed")) return; } catch (e) {}

  // The homepage has no #main; its banner goes above everything else.
  var home = page === "home";
  var main = home ? document.body : document.getElementById("main");
  if (!main) return;
  var text = T[folder];
  var bar = document.createElement("div");
  bar.className = "langbar";
  bar.setAttribute("role", "region");
  bar.setAttribute("lang", folder.split("-")[0]);
  var p = document.createElement("p");
  p.appendChild(document.createTextNode(text[0] + " "));
  var a = document.createElement("a");
  a.href = root + folder + "/" + (home ? "index" : page) + ".html";
  a.textContent = text[1];
  p.appendChild(a);
  var b = document.createElement("button");
  b.type = "button";
  b.setAttribute("aria-label", text[2]);
  b.textContent = "×";
  b.addEventListener("click", function () {
    try { localStorage.setItem("dh-lang-dismissed", "1"); } catch (e) {}
    bar.remove();
  });
  bar.appendChild(p);
  bar.appendChild(b);
  main.insertBefore(bar, main.firstChild);
})();
