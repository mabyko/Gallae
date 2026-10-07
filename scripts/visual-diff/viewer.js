import { parseGraphDoc } from "@coldtea/pr-lens-schema";
import { render } from "@coldtea/pr-lens-renderer";

// Graphs are validated before their text reaches the renderer or the native bridge.
export function drawGraph(json, lens, theme) {
  const graph = parseGraphDoc(JSON.parse(json));
  const drawing = render(graph, { lens, theme });
  return { graph, drawing };
}

if (typeof document !== "undefined") {
  const viewport = document.getElementById("viewport");
  const world = document.getElementById("world");
  let graph, drawing, currentJSON, currentLens, currentTheme;
  let x = 0, y = 0, scale = 1, fitScale = 1, fitted = true, selectedPath;
  let viewportWidth = viewport.clientWidth, viewportHeight = viewport.clientHeight;
  let drag;
  const send = message => window.webkit?.messageHandlers?.visualDiff?.postMessage(message);
  const place = () => { world.style.transform = `translate(${x}px,${y}px) scale(${scale})`; };
  const fit = () => {
    if (!drawing) return;
    fitScale = Math.min((viewport.clientWidth - 40) / drawing.width, (viewport.clientHeight - 40) / drawing.height, 1);
    scale = Math.max(0.05, fitScale);
    x = (viewport.clientWidth - drawing.width * scale) / 2;
    y = (viewport.clientHeight - drawing.height * scale) / 2;
    fitted = true;
    place();
  };
  const zoom = factor => {
    const next = Math.max(0.05, Math.min(4, scale * factor));
    const cx = viewport.clientWidth / 2, cy = viewport.clientHeight / 2;
    x = cx - (cx - x) * next / scale;
    y = cy - (cy - y) * next / scale;
    scale = next; fitted = false; place();
  };
  function select(path) {
    selectedPath = path;
    for (const button of world.querySelectorAll(".node")) button.classList.toggle("selected", button.dataset.path === path);
  }
  function options({ path, reduceMotion }) {
    select(path);
    const svg = world.querySelector("svg");
    if (reduceMotion) svg?.pauseAnimations?.(); else svg?.unpauseAnimations?.();
  }
  window.GallaeLens = {
    load(json, lens, theme) {
      if (json === currentJSON && lens === currentLens && theme === currentTheme) return;
      const result = drawGraph(json, lens, theme);
      const newDocument = json !== currentJSON || lens !== currentLens;
      graph = result.graph; drawing = result.drawing;
      currentJSON = json; currentLens = lens; currentTheme = theme;
      world.innerHTML = drawing.svg;
      world.style.width = `${drawing.width}px`;
      world.style.height = `${drawing.height}px`;
      for (const node of graph.nodes) {
        const box = drawing.atlas.nodes[node.id];
        const file = node.files?.[0];
        if (!box || !file) continue;
        const button = document.createElement("button");
        button.className = "node"; button.dataset.path = file.path;
        button.setAttribute("aria-label", `Open diff for ${file.path}: ${node.label}`);
        button.title = file.path;
        Object.assign(button.style, { left: `${box.x}px`, top: `${box.y}px`, width: `${box.width}px`, height: `${box.height}px` });
        button.addEventListener("click", () => { select(file.path); send({ type: "file", path: file.path }); });
        world.append(button);
      }
      select(selectedPath);
      if (newDocument || fitted) fit(); else place();
      return { title: graph.title, nodes: graph.nodes.length };
    },
    options,
    // Used to verify that reparenting and appearance changes keep the camera intact.
    camera: () => ({ x, y, scale, fitted, width: viewportWidth, height: viewportHeight }),
  };
  document.getElementById("fit").addEventListener("click", fit);
  document.getElementById("zoom-in").addEventListener("click", () => zoom(1.25));
  document.getElementById("zoom-out").addEventListener("click", () => zoom(0.8));
  viewport.addEventListener("pointerdown", event => {
    if (event.target.closest("button") || event.button !== 0) return;
    drag = { px: event.clientX, py: event.clientY, x, y };
    viewport.setPointerCapture(event.pointerId); viewport.classList.add("dragging");
  });
  viewport.addEventListener("pointermove", event => {
    if (!drag) return;
    x = drag.x + event.clientX - drag.px; y = drag.y + event.clientY - drag.py;
    fitted = false; place();
  });
  const stopDrag = () => { drag = undefined; viewport.classList.remove("dragging"); };
  viewport.addEventListener("pointerup", stopDrag);
  viewport.addEventListener("pointercancel", stopDrag);
  viewport.addEventListener("wheel", event => {
    event.preventDefault();
    if (event.ctrlKey || event.metaKey) zoom(Math.exp(-event.deltaY * 0.01));
    else { x -= event.deltaX; y -= event.deltaY; fitted = false; place(); }
  }, { passive: false });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") { event.preventDefault(); send({ type: "escape" }); }
  });
  new ResizeObserver(() => {
    const width = viewport.clientWidth, height = viewport.clientHeight;
    // Reparenting can briefly detach the view. Preserve the same world point at the viewport center.
    if (!width || !height) return;
    if (fitted) fit();
    else {
      x += (width - viewportWidth) / 2;
      y += (height - viewportHeight) / 2;
      place();
    }
    viewportWidth = width; viewportHeight = height;
  }).observe(viewport);
  send({ type: "ready" });
}
