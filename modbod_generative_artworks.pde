import java.nio.IntBuffer;

import com.thomasdiewald.pixelflow.java.DwPixelFlow;
import com.thomasdiewald.pixelflow.java.antialiasing.SMAA.SMAA;
import com.thomasdiewald.pixelflow.java.render.skylight.DwSceneDisplay;
import com.thomasdiewald.pixelflow.java.render.skylight.DwSkyLight;
import com.thomasdiewald.pixelflow.java.utils.DwBoundingSphere;
import com.thomasdiewald.pixelflow.java.utils.DwVertexRecorder;

import peasy.*;

DwSceneDisplay scene_display;
DwSkyLight skylight;
PMatrix3D mat_scene_bounds;
DwPixelFlow context;
SMAA smaa;
PGraphics3D pg_aa;
PeasyCam peasycam;

String sketchPath;
String modelsDir = "/data/models/";
ArrayList<String> modelNames;
PShape model, ground;
int modelIndex = 0;
PVector modelDimensions;
float camz;

void setup() {
  size(600, 900, P3D);
  noStroke();

  // get names of all .obj files in models directory
  sketchPath = sketchPath(); // the dir where this sketch is located
  File modelsPath = new File(sketchPath + modelsDir);
  String[] files = modelsPath.list();
  modelNames = new ArrayList<String>();
  for (String fileName : files) {
    if (getFileExtension(fileName).equals("obj")) {
      modelNames.add(fileName);
    }
  }

  // callback for rendering the scene
  scene_display = new DwSceneDisplay() {
    @Override
      public void display(PGraphics3D canvas) {
      displayScene(canvas);
    }
  };

  // library context
  context = new DwPixelFlow(this);

  // smaa antialiasing
  smaa = new SMAA(context);
  pg_aa = (PGraphics3D) createGraphics(width, height, P3D);
  pg_aa.smooth(8);
  pg_aa.textureSampling(5);

  generateCubeMap();

  setScene();

  //frameRate(1000);
}

String getFileExtension(String fileName) {
  int dotIndex = fileName.lastIndexOf('.');
  return (dotIndex == -1) ? "" : fileName.substring(dotIndex + 1);
}

void generateCubeMap() {
  PGL pgl = beginPGL();
  IntBuffer envMapTextureID = IntBuffer.allocate(1);
  pgl.genTextures(1, envMapTextureID);
  pgl.activeTexture(PGL.TEXTURE2);
  pgl.enable(PGL.TEXTURE_CUBE_MAP);
  pgl.bindTexture(PGL.TEXTURE_CUBE_MAP, envMapTextureID.get(0));

  String[] textureNames = { 
    "posx.jpg", "negx.jpg", "posy.jpg", "negy.jpg", "posz.jpg", "negz.jpg"
  };

  PImage[] textures = new PImage[textureNames.length];
  for (int i=0; i<textures.length; i++) {
    textures[i] = loadImage("/data/cubemap/" + textureNames[i]);
  }

  for (int i=0; i<textures.length; i++) {
    int w = textures[i].width;
    int h = textures[i].height;
    textures[i].loadPixels();
    int[] pix = textures[i].pixels;
    int[] rgbaPixels = new int[pix.length];
    for (int j = 0; j< pix.length; j++) {
      int pixel = pix[j];
      rgbaPixels[j] = 0xFF000000 | ((pixel & 0xFF) << 16) | ((pixel & 0xFF0000) >> 16) | (pixel & 0x0000FF00);
    }
    pgl.texImage2D(PGL.TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, PGL.RGBA, w, h, 0, PGL.RGBA, PGL.UNSIGNED_BYTE, java.nio.IntBuffer.wrap(rgbaPixels));
  }
  pgl.texParameteri(PGL.TEXTURE_CUBE_MAP, PGL.TEXTURE_WRAP_S, PGL.CLAMP_TO_EDGE);
  pgl.texParameteri(PGL.TEXTURE_CUBE_MAP, PGL.TEXTURE_WRAP_T, PGL.CLAMP_TO_EDGE);
  pgl.texParameteri(PGL.TEXTURE_CUBE_MAP, PGL.TEXTURE_WRAP_R, PGL.CLAMP_TO_EDGE);
  pgl.texParameteri(PGL.TEXTURE_CUBE_MAP, PGL.TEXTURE_MIN_FILTER, PGL.LINEAR);
  pgl.texParameteri(PGL.TEXTURE_CUBE_MAP, PGL.TEXTURE_MAG_FILTER, PGL.LINEAR);

  endPGL();
}

void setScene() {
  if (model == null) {
    model = loadShape(modelsDir + modelNames.get(modelIndex));

    // used for calculating model bounding-box
    DwVertexRecorder model_vert_recorder = new DwVertexRecorder(this, model);

    // used to store min and max of model bounding-box
    PVector BBmin = new PVector(0, 0, 0);
    PVector BBmax = new PVector(0, 0, 0);

    // loop through model vertices to find min and max
    for (int i = 0; i < model_vert_recorder.verts.length; i++) {
      float[] vertex = model_vert_recorder.verts[i];
      if (vertex != null) {
        if (vertex[0] < BBmin.x) BBmin.x = vertex[0];
        else if (vertex[0] > BBmax.x) BBmax.x = vertex[0];
        if (vertex[1] < BBmin.y) BBmin.y = vertex[1];
        else if (vertex[1] > BBmax.y) BBmax.y = vertex[1];
        if (vertex[2] < BBmin.z) BBmin.z = vertex[2];
        else if (vertex[2] > BBmax.z) BBmax.z = vertex[2];
      }
    }

    // calc model dimensions from bounding box
    modelDimensions = new PVector(BBmax.x - BBmin.x, BBmax.y - BBmin.y, BBmax.z - BBmin.z);

    // get model center
    PVector sum = BBmin.add(BBmax);
    PVector modelCenter = sum.mult(0.5);

    // translate model to scene center
    model.translate(-modelCenter.x, -modelCenter.y, -modelCenter.z);

    // load ground geometry and set size relative to model
    float maxDimension = max(modelDimensions.x, modelDimensions.z);
    ground = createShape(BOX, maxDimension*7, modelDimensions.y*0.01, maxDimension*7);

    // rotate toward light
    model.rotateX(PI/2);
    ground.rotateX(PI/2);

    // translate ground to base of model
    ground.translate(0, 0, -modelDimensions.y/2);

    // used for computing scene bounding-sphere
    DwVertexRecorder ground_vert_recorder = new DwVertexRecorder(this, ground);

    // compute scene bounding-sphere
    DwBoundingSphere scene_bs = new DwBoundingSphere();
    scene_bs.compute(ground_vert_recorder.verts, ground_vert_recorder.verts_count);

    // used for centering and re-scaling scene
    mat_scene_bounds = scene_bs.getUnitSphereMatrix();

    // set skylight renderer
    skylight = new DwSkyLight(context, scene_display, mat_scene_bounds);

    // camera properties
    float fov = radians(30);
    float aspect = float(width)/float(height);

    // calc distance needed to fit model in viewport
    camz = max((modelDimensions.y/2) / tan(fov/2), (modelDimensions.x/2) / (tan(fov/2) * aspect));

    // init camera
    peasycam = new PeasyCam(this, camz);
    perspective(fov, aspect, camz/10.0, camz*10.0);
  }

  // set parameters
  setParams();

  // restart renderer
  skylight.reset();
}

void setParams() {
  // set camera orientation
  peasycam.setDistance(camz * random(1.1, 1.4));
  peasycam.setRotations(radians(-90  + random(-10, 10)), 0, 0);
  peasycam.lookAt(0, 0, 0);

  // have model face a random direction
  model.rotateZ(random(2*PI));
  
  // model base color
  //colorMode(HSB, 1.0); 
  //float hue = 1;
  //float saturation = 1;
  //float brightness = 1; 
  //color c = color(hue, saturation, brightness);

  // parameters for sky-light
  skylight.sky.param.iterations     = 10;
  skylight.sky.param.solar_azimuth  = 0;
  skylight.sky.param.solar_zenith   = 0;
  skylight.sky.param.sample_focus   = 1; // full sphere sampling
  skylight.sky.param.intensity      = 1.0f;
  skylight.sky.param.rgb            = new float[]{0.12, 0.41, 1}; // natural light: {0.12, 0.41, 1}
  skylight.sky.param.shadowmap_size = 2048; // quality vs. performance

  // parameters for sun-light
  skylight.sun.param.iterations     = 10;
  skylight.sun.param.solar_azimuth  = random(180);
  skylight.sun.param.solar_zenith   = random(90);
  skylight.sun.param.sample_focus   = random(0.5);
  skylight.sun.param.intensity      = 1.0f;
  skylight.sun.param.rgb            = new float[]{1, 0.51, 0.02}; // natural light: {1, 0.51, 0.02}
  skylight.sun.param.shadowmap_size = 2048;

  // parameters for renderer
  skylight.renderer.shader.set("cubemap", 2);
  //skylight.renderer.shader.set("baseColor", red(c), green(c), blue(c));
  skylight.renderer.shader.set("baseColor", 1.0, 1.0, 1.0);
  skylight.renderer.shader.set("reflectMix", 0.0);
  skylight.renderer.shader.set("shadowMix", 1.0);
}

void draw() {
  // when the camera moves, the renderer restarts
  updateCamActiveStatus();
  if (CAM_ACTIVE) {
    skylight.reset();
  } else {
    // start loading next model???
  }

  // update renderer
  skylight.update();

  // antialiasing
  smaa.apply(skylight.renderer.pg_render, pg_aa);

  // display result
  peasycam.beginHUD();
  blendMode(REPLACE);
  image(pg_aa, 0, 0);
  blendMode(BLEND);
  peasycam.endHUD();
}

void displayScene(PGraphics canvas) {
  canvas.colorMode(RGB, 1);

  if (canvas == skylight.renderer.pg_render) {
    canvas.background(0);
  }

  canvas.shape(model);
  //canvas.shape(ground);
}

float[] cam_pos = new float[3];
boolean CAM_ACTIVE = false;

void updateCamActiveStatus() {
  float[] cam_pos_curr = peasycam.getPosition();
  CAM_ACTIVE = false;
  CAM_ACTIVE |= cam_pos_curr[0] != cam_pos[0];
  CAM_ACTIVE |= cam_pos_curr[1] != cam_pos[1];
  CAM_ACTIVE |= cam_pos_curr[2] != cam_pos[2];
  cam_pos = cam_pos_curr;
}

void keyPressed() {
  saveImage();

  // use arrow keys to cycle through models
  if (key == CODED) {
    if (keyCode == RIGHT) {
      model = null;
      modelIndex += 1;
      if (modelIndex > modelNames.size()-1) {
        modelIndex = 0;
      }
    } else if (keyCode == LEFT) {
      model = null;
      modelIndex -= 1;
      if (modelIndex < 0) {
        modelIndex = modelNames.size()-1;
      }
    }
  }
  
  setScene();
}

void saveImage() {
  String timeStamp = str(year()) + "-" + str(month()) + "-" + str(day()) + "-" + str(hour()) + "-" + str(minute()) + "-" + str(second()) + "-" + str(millis());
  save("output/" + timeStamp + ".jpg");
}
