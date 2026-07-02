package com.gurfdev.light_compressor_v2.lightcompressorlibrary.video

import android.graphics.SurfaceTexture
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

class TextureRenderer(
    private val brightness: Float = 0f,
    private val contrast: Float = 1f,
    private val saturation: Float = 1f,
) {

    private val floatSizeBytes = 4
    private val triangleVerticesDataStrideBytes = 5 * floatSizeBytes
    private val triangleVerticesDataPosOffset = 0
    private val triangleVerticesDataUvOffset = 3
    private var mTriangleVertices: FloatBuffer

    private val vertexShader = """uniform mat4 uMVPMatrix;
uniform mat4 uSTMatrix;
attribute vec4 aPosition;
attribute vec4 aTextureCoord;
varying vec2 vTextureCoord;
void main() {
  gl_Position = uMVPMatrix * aPosition;
  vTextureCoord = (uSTMatrix * aTextureCoord).xy;
}
"""

    private val fragmentShader = """#extension GL_OES_EGL_image_external : require
precision mediump float;
varying vec2 vTextureCoord;
uniform samplerExternalOES sTexture;
uniform float uBrightness;
uniform float uContrast;
uniform float uSaturation;
void main() {
  vec4 c = texture2D(sTexture, vTextureCoord);
  vec3 rgb = c.rgb;
  // Color adjust (Phase 9c), CIColorControls-style order: saturation, then
  // brightness (additive), then contrast (around 0.5 mid-grey). Identity at
  // saturation=1, brightness=0, contrast=1, so the no-color path is a no-op.
  float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
  rgb = mix(vec3(luma), rgb, uSaturation);
  rgb = rgb + uBrightness;
  rgb = (rgb - 0.5) * uContrast + 0.5;
  gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), c.a);
}
"""

    private val mMVPMatrix = FloatArray(16)
    private val mSTMatrix = FloatArray(16)

    private var mProgram = 0
    private var mTextureID = -12345
    private var muMVPMatrixHandle = 0
    private var muSTMatrixHandle = 0
    private var maPositionHandle = 0
    private var maTextureHandle = 0
    private var muBrightnessHandle = 0
    private var muContrastHandle = 0
    private var muSaturationHandle = 0

    init {
        val mTriangleVerticesData = floatArrayOf( // X, Y, Z, U, V
            -1.0f, -1.0f, 0f, 0f, 0f,
            1.0f, -1.0f, 0f, 1f, 0f,
            -1.0f, 1.0f, 0f, 0f, 1f,
            1.0f, 1.0f, 0f, 1f, 1f
        )
        mTriangleVertices = ByteBuffer.allocateDirect(
            mTriangleVerticesData.size * floatSizeBytes
        )
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        mTriangleVertices.put(mTriangleVerticesData).position(0)

        Matrix.setIdentityM(mSTMatrix, 0)
    }

    fun getTextureId(): Int = mTextureID

    fun drawFrame(st: SurfaceTexture) {
        checkGlError("onDrawFrame start")
        st.getTransformMatrix(mSTMatrix)

        GLES20.glClearColor(0.0f, 1.0f, 0.0f, 1.0f)
        GLES20.glClear(GLES20.GL_DEPTH_BUFFER_BIT or GLES20.GL_COLOR_BUFFER_BIT)

        GLES20.glUseProgram(mProgram)
        checkGlError("glUseProgram")

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, mTextureID)

        mTriangleVertices.position(triangleVerticesDataPosOffset)
        GLES20.glVertexAttribPointer(
            maPositionHandle, 3, GLES20.GL_FLOAT, false,
            triangleVerticesDataStrideBytes, mTriangleVertices
        )
        checkGlError("glVertexAttribPointer maPosition")
        GLES20.glEnableVertexAttribArray(maPositionHandle)
        checkGlError("glEnableVertexAttribArray maPositionHandle")

        mTriangleVertices.position(triangleVerticesDataUvOffset)
        GLES20.glVertexAttribPointer(
            maTextureHandle, 2, GLES20.GL_FLOAT, false,
            triangleVerticesDataStrideBytes, mTriangleVertices
        )
        checkGlError("glVertexAttribPointer maTextureHandle")
        GLES20.glEnableVertexAttribArray(maTextureHandle)
        checkGlError("glEnableVertexAttribArray maTextureHandle")

        Matrix.setIdentityM(mMVPMatrix, 0)
        GLES20.glUniformMatrix4fv(muMVPMatrixHandle, 1, false, mMVPMatrix, 0)
        GLES20.glUniformMatrix4fv(muSTMatrixHandle, 1, false, mSTMatrix, 0)

        if (muBrightnessHandle >= 0) GLES20.glUniform1f(muBrightnessHandle, brightness)
        if (muContrastHandle >= 0) GLES20.glUniform1f(muContrastHandle, contrast)
        if (muSaturationHandle >= 0) GLES20.glUniform1f(muSaturationHandle, saturation)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        checkGlError("glDrawArrays")
        GLES20.glFinish()
    }

    /**
     * Initializes GL state.  Call this after the EGL surface has been created and made current.
     */
    fun surfaceCreated() {
        mProgram = createProgram()
        if (mProgram == 0) {
            throw RuntimeException("failed creating program")
        }
        maPositionHandle = GLES20.glGetAttribLocation(mProgram, "aPosition")
        checkGlError("glGetAttribLocation aPosition")
        if (maPositionHandle == -1) {
            throw RuntimeException("Could not get attrib location for aPosition")
        }
        maTextureHandle = GLES20.glGetAttribLocation(mProgram, "aTextureCoord")
        checkGlError("glGetAttribLocation aTextureCoord")
        if (maTextureHandle == -1) {
            throw RuntimeException("Could not get attrib location for aTextureCoord")
        }

        muMVPMatrixHandle = GLES20.glGetUniformLocation(mProgram, "uMVPMatrix")
        checkGlError("glGetUniformLocation uMVPMatrix")
        if (muMVPMatrixHandle == -1) {
            throw RuntimeException("Could not get attrib location for uMVPMatrix")
        }

        muSTMatrixHandle = GLES20.glGetUniformLocation(mProgram, "uSTMatrix")
        checkGlError("glGetUniformLocation uSTMatrix")
        if (muSTMatrixHandle == -1) {
            throw RuntimeException("Could not get attrib location for uSTMatrix")
        }

        // Color-adjustment uniforms (Phase 9c). Not fatal if a driver optimizes
        // one out — drawFrame guards on a valid (>= 0) location.
        muBrightnessHandle = GLES20.glGetUniformLocation(mProgram, "uBrightness")
        muContrastHandle = GLES20.glGetUniformLocation(mProgram, "uContrast")
        muSaturationHandle = GLES20.glGetUniformLocation(mProgram, "uSaturation")

        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        mTextureID = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, mTextureID)
        checkGlError("glBindTexture mTextureID")

        GLES20.glTexParameterf(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_NEAREST.toFloat()
        )
        GLES20.glTexParameterf(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR.toFloat()
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE
        )
        checkGlError("glTexParameter")
    }

    private fun loadShader(shaderType: Int, source: String): Int {
        var shader = GLES20.glCreateShader(shaderType)
        checkGlError("glCreateShader type=$shaderType")
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] == 0) {
            GLES20.glDeleteShader(shader)
            shader = 0
        }
        return shader
    }

    private fun createProgram(): Int {
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexShader)
        if (vertexShader == 0) {
            return 0
        }

        val pixelShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentShader)
        if (pixelShader == 0) {
            return 0
        }

        var program = GLES20.glCreateProgram()
        checkGlError("glCreateProgram")
        if (program == 0) {
            return 0
        }
        GLES20.glAttachShader(program, vertexShader)
        checkGlError("glAttachShader")
        GLES20.glAttachShader(program, pixelShader)
        checkGlError("glAttachShader")
        GLES20.glLinkProgram(program)
        val linkStatus = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
        if (linkStatus[0] != GLES20.GL_TRUE) {
            GLES20.glDeleteProgram(program)
            program = 0
        }
        return program
    }

    fun checkGlError(op: String) {
        var error: Int
        if (GLES20.glGetError().also { error = it } != GLES20.GL_NO_ERROR) {
            throw RuntimeException("$op: glError $error")
        }
    }

}