import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { drawGraph } from "./viewer.js";

const example = await readFile("../../Gallae/Resources/VisualDiff/example.graph.json", "utf8");
test("renders both local themes and includes geometry for file navigation", () => {
  const light = drawGraph(example, "architecture", "light");
  const dark = drawGraph(example, "architecture", "dark");
  assert.match(light.drawing.svg, /^<svg/);
  assert.notEqual(light.drawing.svg, dark.drawing.svg);
  assert.deepEqual(light.drawing.atlas, dark.drawing.atlas);
  for (const node of light.graph.nodes) assert.ok(light.drawing.atlas.nodes[node.id]);
});
test("renders data-flow when the imported graph supports it", () => {
  const graph = JSON.parse(example);
  graph.lenses.push("data-flow");
  graph.flows = [{ id: "render", title: "Apply theme", participants: [{ node: "theme" }, { node: "diff" }],
    messages: [{ id: "apply", from: "theme", to: "diff", label: "Apply theme", delta: "modified" }] }];
  const { drawing } = drawGraph(JSON.stringify(graph), "data-flow", "dark");
  assert.match(drawing.svg, /^<svg/);
  assert.ok(drawing.atlas.nodes.theme);
  assert.ok(drawing.atlas.nodes.diff);
});
test("rejects invalid graphs, including broken edge references", () => {
  assert.throws(() => drawGraph('{"kind":"graph"}', "architecture", "dark"));
  const graph = JSON.parse(example);
  graph.edges[0].to = "missing-node";
  assert.throws(() => drawGraph(JSON.stringify(graph), "architecture", "dark"));
});
test("escapes graph labels rather than inserting model text as markup", () => {
  const graph = JSON.parse(example);
  graph.nodes[0].label = '<script>alert("x")</script>';
  const { drawing } = drawGraph(JSON.stringify(graph), "architecture", "dark");
  assert.ok(!drawing.svg.includes("<script>"));
  assert.ok(drawing.svg.includes("&lt;"));
});
test("the shipped renderer has no runtime Node imports", async () => {
  const bundle = await readFile("../../Gallae/Resources/VisualDiff/viewer.js", "utf8");
  assert.ok(!bundle.includes("node:crypto"));
  assert.ok(!bundle.includes("require("));
});
