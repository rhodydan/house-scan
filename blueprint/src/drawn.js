// HTML drawn into the 3D scene with html-in-canvas (https://github.com/WICG/html-in-canvas).
//
// Each surface is a real DOM element, a `drawable` child of the WebGL canvas. Chrome lays it out and paints it, we
// upload that picture into a texture with `texElementSubImage2D`, and show it on a plane anywhere in the scene. Clicks
// still reach the element: every frame we hand Chrome the mapping from the element's box to where the plane lands on
// screen (`updateElementGeometry`), perspective and all, and Chrome hit-tests through it.
//
// Facts the explainer doesn't state, measured in Chrome 157:
// - The uploaded image's top row is texture row 0, so the plane's texture coordinates are flipped.
// - `canvasTransform` maps the element's CSS-pixel box into the canvas's CSS pixels, not its drawing-buffer pixels.
// - The painted picture can be bigger than the element's box (outlines, text shadows), so the upload names the box as
//   its source rect; without it the copy overflows the texture and fails.
// - Once an element has geometry, getBoundingClientRect reports where it appears on screen, transform applied.
import * as THREE from 'three';

export const supported = () =>
  typeof WebGL2RenderingContext !== 'undefined' && 'texElementSubImage2D' in WebGL2RenderingContext.prototype &&
  'updateElementGeometry' in HTMLCanvasElement.prototype;

export class DrawnLayer {
  /** `metresPerPixel` sets how big an element is in the scene: a 100 px wide element at 0.01 is 1 m wide. */
  constructor(renderer, camera) {
    this.renderer = renderer;
    this.camera = camera;
    this.canvas = renderer.domElement;
    this.gl = renderer.getContext();
    this.surfaces = new Map();
    this.canvas.setAttribute('content', 'drawable');
    this.canvas.addEventListener('paint', (event) => {
      for (const element of event.changedElements ?? []) this.surfaces.get(element)?.upload();
    });
  }

  /** Makes `element` a drawable child of the canvas and returns the mesh that shows it. */
  add(element, { metresPerPixel = 0.01, material = {} } = {}) {
    element.setAttribute('drawable', '');
    this.canvas.appendChild(element);
    const surface = new Surface(this, element, metresPerPixel, material);
    this.surfaces.set(element, surface);
    this.canvas.requestPaint();
    return surface;
  }

  remove(surface) {
    this.surfaces.delete(surface.element);
    this.canvas.clearElementGeometry?.(surface.element);
    surface.element.remove();
    surface.mesh.removeFromParent();
    surface.texture?.dispose();
  }

  /** After the frame is drawn: tell Chrome where each visible element now sits on screen, so clicks find it. */
  updateHitTesting() {
    const width = this.canvas.clientWidth, height = this.canvas.clientHeight;
    // Clip space to the canvas's CSS pixels. Depth is dropped: hit testing only needs where things land.
    const viewport = new THREE.Matrix4().set(
      width / 2, 0, 0, width / 2,
      0, -height / 2, 0, height / 2,
      0, 0, 0, 0,
      0, 0, 0, 1);
    const toClip = new THREE.Matrix4().multiplyMatrices(this.camera.projectionMatrix, this.camera.matrixWorldInverse);
    for (const surface of this.surfaces.values()) surface.updateGeometry(viewport, toClip);
  }
}

class Surface {
  constructor(layer, element, metresPerPixel, material) {
    this.layer = layer;
    this.element = element;
    this.metresPerPixel = metresPerPixel;
    this.size = { css: [0, 0], grid: [0, 0] };
    const geometry = new THREE.PlaneGeometry(1, 1);
    const uv = geometry.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setY(i, 1 - uv.getY(i)); // the element's top is texture row 0
    this.material = new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, side: THREE.DoubleSide, ...material });
    this.mesh = new THREE.Mesh(geometry, this.material);
    this.mesh.visible = false; // until the first paint
    this.interactive = true;
  }

  setScale(metresPerPixel) {
    this.metresPerPixel = metresPerPixel;
    this.mesh.scale.set(this.size.css[0] * metresPerPixel, this.size.css[1] * metresPerPixel, 1);
  }

  /** Chrome painted a new picture of the element: copy it into the texture, reallocating if the size changed. */
  upload() {
    const { canvas, gl, renderer } = this.layer;
    const grid = canvas.getElementImageDefaultSize(this.element);
    const w = Math.max(1, Math.round(grid.width)), h = Math.max(1, Math.round(grid.height));
    if (!this.texture || w !== this.size.grid[0] || h !== this.size.grid[1]) {
      this.texture?.dispose();
      this.texture = new THREE.DataTexture(new Uint8Array(w * h * 4), w, h);
      this.texture.colorSpace = THREE.SRGBColorSpace;
      this.texture.minFilter = THREE.LinearFilter;
      this.texture.generateMipmaps = false;
      this.texture.needsUpdate = true;
      renderer.initTexture(this.texture);
      this.material.map = this.texture;
      this.material.needsUpdate = true;
      this.size = { css: [this.element.offsetWidth, this.element.offsetHeight], grid: [w, h] };
      this.setScale(this.metresPerPixel);
      this.onResize?.(this.size.css);
    }
    gl.bindTexture(gl.TEXTURE_2D, renderer.properties.get(this.texture).__webglTexture);
    // Copy exactly the element's box. Its painted picture can be bigger (outlines, text glow spill past the box), and
    // without a source rect the copy overflows the texture and fails.
    const [cw, ch] = this.size.css;
    // three.js leaves the unpack state from its own last upload; after an image texture (flipY) this copy would land
    // upside down.
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.texElementSubImage2D(gl.TEXTURE_2D, 0, 0, 0, this.element, { sx: 0, sy: 0, swidth: cw, sheight: ch, width: w, height: h });
    renderer.resetState(); // three.js caches GL bindings; we changed one behind its back
    this.mesh.visible = true;
  }

  updateGeometry(viewport, toClip) {
    const { canvas } = this.layer;
    const [w, h] = this.size.css;
    if (!this.interactive || !w || !visibleInScene(this.mesh)) return canvas.clearElementGeometry(this.element);
    // Element pixels (y down from the top-left) to the unit plane (y up, centred), then into the world.
    const fromElement = new THREE.Matrix4().set(
      1 / w, 0, 0, -0.5,
      0, -1 / h, 0, 0.5,
      0, 0, 1, 0,
      0, 0, 0, 1);
    this.mesh.updateWorldMatrix(true, false);
    const total = viewport.clone().multiply(toClip).multiply(this.mesh.matrixWorld).multiply(fromElement);
    // Any corner behind the camera would fold the picture inside out, so stop hit testing it.
    const e = total.elements;
    for (const [x, y] of [[0, 0], [w, 0], [0, h], [w, h]]) {
      if (e[3] * x + e[7] * y + e[15] <= 0) return canvas.clearElementGeometry(this.element);
    }
    this.matrix = DOMMatrix.fromFloat64Array(new Float64Array(e));
    canvas.updateElementGeometry(this.element, { canvasTransform: this.matrix });
  }

}

function visibleInScene(object) {
  for (let o = object; o; o = o.parent) if (!o.visible) return false;
  return object.material.opacity > 0.3;
}
