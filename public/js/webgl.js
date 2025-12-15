let webgl2Supported = (typeof WebGL2RenderingContext !== 'undefined');
let webgl_fallback = false;
let gl;

function init_webgl() {
  let webglOptions = {
    alpha: true, //Boolean that indicates if the canvas contains an alpha buffer.
    antialias: true,  //Boolean that indicates whether or not to perform anti-aliasing.
    depth: 32,  //Boolean that indicates that the drawing buffer has a depth buffer of at least 16 bits.
    failIfMajorPerformanceCaveat: false,  //Boolean that indicates if a context will be created if the system performance is low.
    powerPreference: "default", //A hint to the user agent indicating what configuration of GPU is suitable for the WebGL context. Possible values are:
    premultipliedAlpha: true,  //Boolean that indicates that the page compositor will assume the drawing buffer contains colors with pre-multiplied alpha.
    preserveDrawingBuffer: true,  //If the value is true the buffers will not be cleared and will preserve their values until cleared or overwritten by the author.
    stencil: true, //Boolean that indicates that the drawing buffer has a stencil buffer of at least 8 bits.
  }

  const $canvasgl = document.querySelector("canvas");

  if (webgl2Supported) {
    gl = $canvasgl.getContext('webgl2', webglOptions);
    if (!gl) {
      throw new Error('The browser supports WebGL2, but initialization failed.');
    }
  }
  if (!gl) {
    webgl_fallback = true;
    gl = $canvasgl.getContext('webgl', webglOptions);

    if (!gl) {
      throw new Error('The browser does not support WebGL');
    }

    let vaoExt = gl.getExtension("OES_vertex_array_object");
    if (!vaoExt) {
      throw new Error('The browser supports WebGL, but not the OES_vertex_array_object extension');
    }
    gl.createVertexArray = vaoExt.createVertexArrayOES,
      gl.deleteVertexArray = vaoExt.deleteVertexArrayOES,
      gl.isVertexArray = vaoExt.isVertexArrayOES,
      gl.bindVertexArray = vaoExt.bindVertexArrayOES,
      gl.createVertexArray = vaoExt.createVertexArrayOES;
  }
  if (!gl) {
    throw new Error('The browser supports WebGL, but initialization failed.');
  }
}

const glShaders = [];
const glPrograms = [];
const glUniformLocations = [];
const glVertexArrays = [];
const glBuffers = [];
const glTextures = [null];
const glFramebuffers = [null];
const glRenderbuffers = [null];

const glViewport = (x, y, width, height) => gl.viewport(x, y, width, height);
const glClearColor = (r, g, b, a) => gl.clearColor(r, g, b, a);
const glClearDepthf = (d) => gl.clearDepth(d);
const glClear = (x) => gl.clear(x);
const glColorMask = (r, g, b, a) => gl.colorMask(r, g, b, a);
const glDepthMask = (mask) => gl.depthMask(mask);
const glStencilMask = (mask) => gl.stencilMask(mask);
const glCullFace = (mode) => gl.cullFace(mode);
const glFrontFace = (mode) => gl.frontFace(mode);
const glEnable = (cap) => gl.enable(cap);
const glDisable = (cap) => gl.disable(cap);
const glDepthFunc = (x) => gl.depthFunc(x);
const glBlendFunc = (x, y) => gl.blendFunc(x, y);
const glBlendFuncSeparate = (srcRGB, dstRGB, srcAlpha, dstAlpha) => gl.blendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha);
const glStencilFunc = (func, ref, mask) => gl.stencilFunc(func, ref, mask);
const glStencilOp = (fail, zfail, zpass) => gl.stencilOp(fail, zfail, zpass);
const glStencilOpSeparate = (face, fail, zfail, zpass) => gl.stencilOpSeparate(face, fail, zfail, zpass);
const glCreateProgram = () => {
  glPrograms.push(gl.createProgram());
  return glPrograms.length - 1;
};
const glCreateShader = (type) => {
  glShaders.push(gl.createShader(type));
  return glShaders.length - 1;
};
const glShaderSource = (shader, count, string, length) => {
  const strs = new Uint32Array(memory.buffer, string, count);
  const lens = new Uint32Array(memory.buffer, length, count);
  let source = '';
  for (let i = 0; i < count; i++) {
    source += read_char_string(strs[i], lens[i]) + '\n';
  }
  gl.shaderSource(glShaders[shader], source);
};
const glCompileShader = (shader) => gl.compileShader(glShaders[shader]);
const glAttachShader = (program, shader) => gl.attachShader(glPrograms[program], glShaders[shader]);
const glGetShaderiv = (shader, pname, params) => {
  const buffer = new Uint32Array(memory.buffer, params, 1);
  buffer[0] = gl.getShaderParameter(glShaders[shader], pname);
};
const glGetShaderInfoLog = (shader, bufSize, length, infoLog) => {
  const log = gl.getShaderInfoLog(glShaders[shader]);
  if (log.length) console.log(log);
};
const glBindAttribLocation = (programId, index, namePtr, nameLen) => gl.bindAttribLocation(glPrograms[programId], index, read_char_string(namePtr, nameLen));
const glLinkProgram = (program) => {
  gl.linkProgram(glPrograms[program]);
  if (!gl.getProgramParameter(glPrograms[program], gl.LINK_STATUS)) {
    throw ("Error linking program:" + gl.getProgramInfoLog(glPrograms[program]));
  }
}
const glGetProgramiv = (program, pname, params) => {
  const buffer = new Uint32Array(memory.buffer, params, 1);
  buffer[0] = gl.getProgramParameter(glPrograms[program], pname);
};
const glGetProgramInfoLog = (program, bufSize, length, infoLog) => {
  console.log(gl.getProgramInfoLog(glPrograms[program]));
};
const glGetAttribLocation = (programId, namePtr) => gl.getAttribLocation(glPrograms[programId], read_char_string_zero(namePtr));
const glGetUniformLocation = (programId, namePtr) => {
  glUniformLocations.push(gl.getUniformLocation(glPrograms[programId], read_char_string_zero(namePtr)));
  return glUniformLocations.length - 1;
};
const glUniform1i = (locationId, x) => gl.uniform1i(glUniformLocations[locationId], x);
const glUniform1f = (locationId, x) => gl.uniform1f(glUniformLocations[locationId], x);
const glUniform1fv = (locationId, count, value) => {
  let arr = new Float32Array(memory.buffer, value, count);
  gl.uniform1fv(glUniformLocations[locationId], arr);
}
const glUniform2f = (locationId, x, y) => gl.uniform2f(glUniformLocations[locationId], x, y);
const glUniform2fv = (locationId, count, value) => {
  let arr = new Float32Array(memory.buffer, value, count * 2);
  gl.uniform2fv(glUniformLocations[locationId], arr);
}
const glUniform3f = (locationId, x, y, z) => gl.uniform3f(glUniformLocations[locationId], x, y, z);
const glUniform3fv = (locationId, count, value) => {
  let arr = new Float32Array(memory.buffer, value, count * 3);
  gl.uniform3fv(glUniformLocations[locationId], arr);
}
const glUniform4f = (locationId, x, y, z, w) => gl.uniform4fv(glUniformLocations[locationId], [x, y, z, w]);
const glUniform4fv = (locationId, count, value) => {
  let arr = new Float32Array(memory.buffer, value, count * 4);
  gl.uniform4fv(glUniformLocations[locationId], arr);
}
const glUniformMatrix3fv = (locationId, count, transpose, dataPtr) => {
  const floats = new Float32Array(memory.buffer, dataPtr, count * 9);
  gl.uniformMatrix3fv(glUniformLocations[locationId], transpose, floats);
};
const glUniformMatrix4fv = (locationId, count, transpose, dataPtr) => {
  const floats = new Float32Array(memory.buffer, dataPtr, count * 16);
  gl.uniformMatrix4fv(glUniformLocations[locationId], transpose, floats);
};
const glCreateBuffer = () => {
  glBuffers.push(gl.createBuffer());
  return glBuffers.length - 1;
};
const glGenBuffers = (num, dataPtr) => {
  const buffers = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    const b = glCreateBuffer();
    buffers[n] = b;
  }
};
const glDetachShader = (program, shader) => {
  gl.detachShader(glPrograms[program], glShaders[shader]);
};
const glDeleteProgram = (id) => {
  gl.deleteProgram(glPrograms[id]);
  glPrograms[id] = undefined;
};
const glDeleteBuffer = (id) => {
  gl.deleteBuffer(glPrograms[id]);
  glPrograms[id] = undefined;
};
const glDeleteBuffers = (num, dataPtr) => {
  const buffers = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    gl.deleteBuffer(buffers[n]);
    glBuffers[buffers[n]] = undefined;
  }
};
const glDeleteShader = (id) => {
  gl.deleteShader(glShaders[id]);
  glShaders[id] = undefined;
};
const glBindBuffer = (target, bufferId) => gl.bindBuffer(target, glBuffers[bufferId]);
const glBufferData = (target, size, dataPtr, usage) => {
  if (size === 0) return;
  const data = new Uint8Array(memory.buffer, dataPtr, size);
  gl.bufferData(target, data, usage);
}
const glBufferSubData = (target, offset, size, dataPtr) => {
  const data = new Uint8Array(memory.buffer, dataPtr, size);
  gl.bufferSubData(target, offset, data, drawType);
}
const glUseProgram = (programId) => gl.useProgram(glPrograms[programId]);
const glEnableVertexAttribArray = (x) => gl.enableVertexAttribArray(x);
const glDisableVertexAttribArray = (x) => gl.disableVertexAttribArray(x);
const glVertexAttribPointer = (attribLocation, size, type, normalize, stride, offset) => {
  gl.vertexAttribPointer(attribLocation, size, type, normalize, stride, offset);
}
const glVertexAttribDivisor = (index, divisor) => gl.vertexAttribDivisor(index, divisor);
const glDrawArrays = (type, offset, count) => gl.drawArrays(type, offset, count);
const glDrawElements = (mode, count, type, offset) => gl.drawElements(mode, count, type, offset);
const glDrawElementsInstanced = (mode, count, type, offset, instancecount) => gl.drawElementsInstanced(mode, count, type, offset, instancecount);

const glCreateTexture = () => {
  glTextures.push(gl.createTexture());
  return glTextures.length - 1;
};
const glLoadTexture = (urlPtr, urlLen) => {
  const url = read_char_string(urlPtr, urlLen);
  return loadImageTexture(url);
}
function createTextureFromImage(image, texture, minFilter, magFilter, wrapS, wrapT) {
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, minFilter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, magFilter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrapS);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrapT);
  if (minFilter == gl.NEAREST_MIPMAP_NEAREST ||
    minFilter == gl.LINEAR_MIPMAP_NEAREST ||
    minFilter == gl.NEAREST_MIPMAP_LINEAR ||
    minFilter == gl.LINEAR_MIPMAP_LINEAR) {
    gl.generateMipmap(gl.TEXTURE_2D);
  }
  glBindTexture(gl.TEXTURE_2D, null);
}
function loadImageTexture(url, minFilter, magFilter, wrapS, wrapT) {
  var id = glCreateTexture();
  var texture = glTextures[id];
  texture.image = new Image();
  texture.image.crossOrigin = '';
  texture.image.onload = function () {
    createTextureFromImage(texture.image, texture, minFilter, magFilter, wrapS, wrapT)
  }
  texture.image.src = url;
  return id;
}
const glGenTextures = (num, dataPtr) => {
  const textures = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    const b = glCreateTexture();
    textures[n] = b;
  }
}
const glDeleteTextures = (num, dataPtr) => {
  const textures = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    gl.deleteTexture(glTextures[textures[n]]);
    glTextures[textures[n]] = undefined;
  }
};
const glBindTexture = (target, textureId) => gl.bindTexture(target, glTextures[textureId]);
const glTexImage2D = (target, level, internalFormat, width, height, border, format, type, dataPtr) => {
  let data;
  if (!dataPtr) {
    data = null;
  } else if (type == gl.UNSIGNED_BYTE) {
    data = new Uint8Array(memory.buffer, dataPtr);
  } else if (type == gl.FLOAT) {
    data = new Float32Array(memory.buffer, dataPtr);
  } else if (type == gl.HALF_FLOAT) {
    data = new Uint16Array(memory.buffer, dataPtr);
  }
  gl.texImage2D(target, level, internalFormat, width, height, border, format, type, data);
};
const glTexSubImage2D = (target, level, xoffset, yoffset, width, height, format, type, dataPtr) => {
  let data;
  if (!dataPtr) {
    data = null;
  } else if (type == gl.UNSIGNED_BYTE) {
    data = new Uint8Array(memory.buffer, dataPtr);
  } else if (type == gl.FLOAT) {
    data = new Float32Array(memory.buffer, dataPtr);
  } else if (type == gl.HALF_FLOAT) {
    data = new Uint16Array(memory.buffer, dataPtr);
  }
  gl.texSubImage2D(target, level, xoffset, yoffset, width, height, format, type, data);
}
function jsLoadTextureIMG(dataPtr, dataLen, mimePtr, mimeLen, widthPtr, heightPtr, minFilter, magFilter, wrapS, wrapT) {
  const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
  const textureId = glCreateTexture();
  const img = new Image();
  // images.push(img); // track loading progress
  const mime = read_char_string(mimePtr, mimeLen);
  img.src = URL.createObjectURL(new Blob([data], { type: mime }));
  img.onload = () => {
    if (widthPtr) new Uint16Array(memory.buffer, widthPtr, 1)[0] = img.width;
    if (heightPtr) new Uint16Array(memory.buffer, heightPtr, 1)[0] = img.height;
    createTextureFromImage(img, glTextures[textureId], minFilter, magFilter, wrapS, wrapT);
  };
  return textureId;
}
const glTexParameteri = (target, pname, param) => gl.texParameteri(target, pname, param);
const glGenerateMipmap = (target) => gl.generateMipmap(target);
const glActiveTexture = (texture) => gl.activeTexture(texture);
const glCreateVertexArray = () => {
  glVertexArrays.push(gl.createVertexArray());
  return glVertexArrays.length - 1;
};
const glGenVertexArrays = (num, dataPtr) => {
  const vaos = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    const b = glCreateVertexArray();
    vaos[n] = b;
  }
}
const glDeleteVertexArrays = (num, dataPtr) => {
  const vaos = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    gl.glCreateTexture(vaos[n]);
    glVertexArrays[vaos[n]] = undefined;
  }
};
const glBindVertexArray = (id) => gl.bindVertexArray(glVertexArrays[id]);
const glPixelStorei = (pname, param) => gl.pixelStorei(pname, param);
const glReadPixels = (x, y, w, h, format, type, pixels) => {
  const data = new Uint8Array(memory.buffer, pixels);
  gl.readPixels(x, y, w, h, format, type, data);
}
const glGetError = () => gl.getError();
const glCreateFramebuffer = () => {
  glFramebuffers.push(gl.createFramebuffer());
  return glFramebuffers.length - 1;
}
const glBindFramebuffer = (target, id) => gl.bindFramebuffer(target, glFramebuffers[id]);
const glDeleteFramebuffer = (id) => {
  gl.deleteFramebuffer(glFramebuffers[id]);
  glFramebuffers[id] = undefined;
}
const glGenFramebuffers = (n, framebuffers) => {
  const buffers = new Uint32Array(memory.buffer, framebuffers, n);
  for (let i = 0; i < n; i++) {
    buffers[i] = glCreateFramebuffer();
  }
}
const glDeleteFramebuffers = (n, framebuffers) => {
  const buffers = new Uint32Array(memory.buffer, framebuffers, n);
  for (let i = 0; i < n; i++) {
    glDeleteFramebuffer(buffers[i]);
  }
}
const glCheckFramebufferStatus = (target) => gl.checkFramebufferStatus(target);
const glCreateRenderbuffer = () => {
  glRenderbuffers.push(gl.createRenderbuffer());
  return glRenderbuffers.length - 1;
}
const glBindRenderbuffer = (target, id) => gl.bindRenderbuffer(target, glRenderbuffers[id]);
const glDeleteRenderbuffer = (id) => {
  gl.deleteRenderbuffer(glRenderbuffers[id]);
  glRenderbuffers[id] = undefined;
}
const glGenRenderbuffers = (n, renderbuffers) => {
  const buffers = new Uint32Array(memory.buffer, renderbuffers, n);
  for (let i = 0; i < n; i++) {
    buffers[i] = glCreateRenderbuffer();
  }
}
const glDeleteRenderbuffers = (n, renderbuffers) => {
  const buffers = new Uint32Array(memory.buffer, renderbuffers, n);
  for (let i = 0; i < n; i++) {
    glDeleteRenderbuffer(buffers[i]);
  }
}
const glRenderbufferStorage = (target, internalFormat, width, height) => gl.renderbufferStorage(target, internalFormat, width, height);
const glRenderbufferStorageMultisample = (target, samples, internalFormat, width, height) => gl.renderbufferStorageMultisample(target, samples, internalFormat, width, height);
const glFramebufferTexture2D = (target, attachment, textarget, texture, level) => gl.framebufferTexture2D(target, attachment, textarget, glTextures[texture], level);
const glFramebufferRenderbuffer = (target, attachment, renderbuffertarget, renderbuffer) => gl.framebufferRenderbuffer(target, attachment, renderbuffertarget, glRenderbuffers[renderbuffer]);
const glBlitFramebuffer = (srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter) => gl.blitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1, mask, filter);
const glDrawBuffers = (n, drawBuffers) => {
  const buffers = new Uint32Array(memory.buffer, drawBuffers, n);
  gl.drawBuffers(buffers);
};
const glGetIntegerv = (pname, param) => {
  let result = gl.getParameter(pname);
  if (!result) result = new Uint32Array([0]);
  const buffers = new Uint32Array(memory.buffer, param, result.length);
  for (let i = 0; i < result.length; i++) {
    buffers[i] = result[i];
  }
}

const webgl_env = {
  glLoadTexture,
  glDeleteProgram,
  glDetachShader,
  glDeleteShader,
  glViewport,
  glClearColor,
  glClearDepthf,
  glCullFace,
  glFrontFace,
  glEnable,
  glDisable,
  glDepthFunc,
  glBlendFunc,
  glBlendFuncSeparate,
  glStencilFunc,
  glStencilOp,
  glStencilOpSeparate,
  glClear,
  glColorMask,
  glDepthMask,
  glStencilMask,
  glCreateProgram,
  glCreateShader,
  glShaderSource,
  glCompileShader,
  glAttachShader,
  glGetShaderiv,
  glGetShaderInfoLog,
  glBindAttribLocation,
  glLinkProgram,
  glGetProgramiv,
  glGetProgramInfoLog,
  glGetAttribLocation,
  glGetUniformLocation,
  glUniform1i,
  glUniform1f,
  glUniform1fv,
  glUniform2f,
  glUniform2fv,
  glUniform3f,
  glUniform3fv,
  glUniform4f,
  glUniform4fv,
  glUniformMatrix3fv,
  glUniformMatrix4fv,
  glCreateBuffer,
  glGenBuffers,
  glDeleteBuffer,
  glDeleteBuffers,
  glBindBuffer,
  glBufferData,
  glBufferSubData,
  glUseProgram,
  glEnableVertexAttribArray,
  glDisableVertexAttribArray,
  glVertexAttribPointer,
  glVertexAttribDivisor,
  glDrawArrays,
  glDrawElements,
  glDrawElementsInstanced,
  glCreateTexture,
  glGenTextures,
  glDeleteTextures,
  glBindTexture,
  glTexImage2D,
  glTexSubImage2D,
  jsLoadTextureIMG,
  glTexParameteri,
  glGenerateMipmap,
  glActiveTexture,
  glCreateVertexArray,
  glGenVertexArrays,
  glDeleteVertexArrays,
  glBindVertexArray,
  glPixelStorei,
  glReadPixels,
  glGetError,
  glGenFramebuffers,
  glBindFramebuffer,
  glDeleteFramebuffers,
  glCheckFramebufferStatus,
  glGenRenderbuffers,
  glBindRenderbuffer,
  glDeleteRenderbuffers,
  glRenderbufferStorage,
  glRenderbufferStorageMultisample,
  glFramebufferTexture2D,
  glFramebufferRenderbuffer,
  glBlitFramebuffer,
  glDrawBuffers,
  glGetIntegerv,
};
