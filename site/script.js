/* OtterIsland — page de présentation.
 *
 * Trois réglages à connaître, juste en dessous. Tout le reste fonctionne sans.
 * Aucune requête vers un service tiers : rien n'est chargé hors de cette page.
 */

// 1. Où mène le bouton « Télécharger ».
//    Par défaut : le dernier .dmg publié sur GitHub.
//    Pour passer par un autre endroit (forum, page de dépôt…), mets son adresse ici.
const DOWNLOAD_URL = "https://github.com/RoYaL63/OtterIsland/releases/latest/download/OtterIsland.dmg";

// 2. La vidéo de présentation. Laisse les deux vides pour masquer la section.
//    - mp4 : chemin d'un fichier posé dans site/assets (ex. "assets/presentation.mp4")
//    - youtube : l'identifiant de la vidéo (ex. "dQw4w9WgXcQ"), lue via youtube-nocookie.com
const VIDEO = { mp4: "assets/presentation.mp4", poster: "assets/presentation-poster.jpg", youtube: "" };

// 3. (Rien à faire) La version affichée est écrite au déploiement, depuis project.yml.

document.querySelectorAll("[data-download]").forEach((a) => { a.href = DOWNLOAD_URL; });

// Version : le workflow remplace {{VERSION}} ; en aperçu local, on ne montre rien.
document.querySelectorAll("[data-version]").forEach((el) => {
  const version = el.textContent.trim();
  if (version && !version.startsWith("{{")) {
    el.closest("[data-version-line]")?.removeAttribute("hidden");
  }
});

// Vidéo.
(function () {
  const box = document.getElementById("video-box");
  const section = document.getElementById("video");
  if (!box || !section) return;
  if (VIDEO.mp4) {
    const video = document.createElement("video");
    video.controls = true;
    video.preload = "metadata";
    video.playsInline = true;
    if (VIDEO.poster) video.poster = VIDEO.poster;
    video.src = VIDEO.mp4;
    box.appendChild(video);
  } else if (VIDEO.youtube) {
    const frame = document.createElement("iframe");
    frame.src = "https://www.youtube-nocookie.com/embed/" + encodeURIComponent(VIDEO.youtube) + "?rel=0";
    frame.title = "Présentation d'OtterIsland";
    frame.loading = "lazy";
    frame.allow = "accelerometer; encrypted-media; picture-in-picture; fullscreen";
    frame.allowFullscreen = true;
    box.appendChild(frame);
  } else {
    return;
  }
  section.hidden = false;
  document.querySelectorAll("[data-needs-video]").forEach((el) => { el.hidden = false; });
})();

// Boutons « Copier ».
document.querySelectorAll(".copy").forEach((button) => {
  button.addEventListener("click", async () => {
    const target = document.querySelector(button.dataset.copy);
    if (!target) return;
    const text = target.innerText.trim();
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      // Repli : sélection manuelle du texte.
      const range = document.createRange();
      range.selectNodeContents(target);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      document.execCommand("copy");
      selection.removeAllRanges();
    }
    const label = button.textContent;
    button.textContent = "Copié ✓";
    setTimeout(() => { button.textContent = label; }, 1600);
  });
});
