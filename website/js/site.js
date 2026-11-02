
const HN = {
  VERSION: "2.3.1",
  DMG_URL: "downloads/HockeyNow.dmg",
  EMAIL: "avdgapps@gmail.com",
};

document.querySelectorAll("[data-dmg]").forEach((a) => { a.href = HN.DMG_URL; a.setAttribute("download", ""); });
document.querySelectorAll("[data-version]").forEach((el) => { el.textContent = HN.VERSION; });

/* mobile nav */
const nav = document.querySelector(".nav");
document.querySelector(".menu-btn")?.addEventListener("click", () => {
  const open = nav.classList.toggle("open");
  document.querySelector(".menu-btn").setAttribute("aria-expanded", open);
});
document.querySelectorAll(".nav-links a").forEach((a) => a.addEventListener("click", () => nav.classList.remove("open")));

/* scroll reveal */
const io = "IntersectionObserver" in window
  ? new IntersectionObserver((entries) => entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { threshold: 0.12, rootMargin: "0px 0px -6% 0px" })
  : null;
document.querySelectorAll(".reveal").forEach((el) => (io ? io.observe(el) : el.classList.add("in")));

/* fit fixed-size mock stages to their container */
function fitStages() {
  document.querySelectorAll(".stage-fit").forEach((box) => {
    const st = box.querySelector(".stage");
    const w = +box.dataset.w, h = +box.dataset.h;
    box.style.maxWidth = w + "px";
    const s = Math.min(1, box.clientWidth / w);
    st.style.width = w + "px"; st.style.height = h + "px";
    st.style.transform = `scale(${s})`;
    box.style.height = h * s + "px";
  });
}
fitStages();
addEventListener("resize", fitStages);
addEventListener("load", fitStages);

/* notch demo: auto-expands/collapses, and follows the pointer */
document.querySelectorAll(".notch[data-auto]").forEach((n) => {
  let hovered = false;
  const tick = () => { if (!hovered) n.classList.toggle("open"); };
  n.classList.add("open");
  let timer = setInterval(tick, 3600);
  n.addEventListener("pointerenter", () => { hovered = true; n.classList.add("open"); });
  n.addEventListener("pointerleave", () => { hovered = false; });
});

/* accent colour demo */
document.querySelectorAll("[data-accent-demo]").forEach((demo) => {
  const target = demo.closest("[data-accent-scope]") || document.body;
  demo.querySelectorAll(".swatch").forEach((sw) => sw.addEventListener("click", () => {
    demo.querySelectorAll(".swatch").forEach((x) => x.classList.remove("on"));
    sw.classList.add("on");
    const c = sw.style.getPropertyValue("--c");
    target.style.setProperty("--accent", c);
    target.style.setProperty("--accent-2", c);
  }));
});

/* features sub-nav highlight */
const links = [...document.querySelectorAll(".subnav a")];
if (links.length && io) {
  const map = new Map(links.map((a) => [a.getAttribute("href").slice(1), a]));
  const so = new IntersectionObserver((es) => es.forEach((e) => {
    if (e.isIntersecting) { links.forEach((l) => l.classList.remove("on")); const a = map.get(e.target.id); a?.classList.add("on"); a?.scrollIntoView({ inline: "center", block: "nearest" }); }
  }), { rootMargin: "-35% 0px -55% 0px" });
  map.forEach((_, id) => { const el = document.getElementById(id); if (el) so.observe(el); });
}

/* Drop-in demo videos.
 * Put an .mp4 in /media and it replaces the matching mockup automatically, e.g.
 *   <div class="media-slot" data-video="media/notch.mp4"> …mockup… </div>
 * If the file is missing, the mockup stays. */
document.querySelectorAll(".media-slot[data-video]").forEach((slot) => {
  const v = document.createElement("video");
  v.muted = true; v.loop = true; v.playsInline = true; v.autoplay = true; v.preload = "metadata";
  v.setAttribute("aria-label", slot.dataset.label || "HockeyNow demo");
  v.addEventListener("loadeddata", () => {
    slot.replaceChildren(v);
    v.play().catch(() => { v.controls = true; });
  }, { once: true });
  v.src = slot.dataset.video;
});