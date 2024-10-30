let UNIT=1;
let canvasWidth=1400;
let canvasHeight=600;
let last = 0;
let img = undefined;
let planetCount=3;
// let startBalls=22400;
let startBalls=25*canvasWidth;
let pendingBalls=400;
let length = pendingBalls+startBalls;
let initColorValues= [[200,30,60],[20,180,10],[40,80,210],[180,40,233],[0,230,215]];
let colorValues=[];
let worker=undefined;
let ctx;
let timer=undefined;

let pause=false;
let showShips=true;

function getHex(n){
  return n.toString(16).padStart(2, '0');
}
function getHexColor(i,j){
  return getHex(initColorValues[i][j]);
}

function setColorPickers(anz){
  console.log("setColorPickers: anz=", anz);
  const div = document.getElementById('colorList');
  div.innerHTML=' ';
  for (let i=0; i<anz; i++){
    const labelText = "Farbe Stern " + (i+1);
    // Create label element
    const label = document.createElement('label');
    label.setAttribute('for', labelText);
    label.textContent = labelText;

    // Create color input element
    const colorInput = document.createElement('input');
    colorInput.setAttribute('type', 'color');
    colorInput.setAttribute('id', 'color'+i);
    if(i < colorValues.length){
      colorInput.value=colorValues[i];
    }
    else if(i < initColorValues.length){
      colorInput.value="#" + getHexColor(i,0) + getHexColor(i,1) + getHexColor(i,2);
      colorValues[i] = colorInput.value;
    }
    else {
      colorInput.value="#" + getHex(Math.floor(256*Math.random())) + getHex(Math.floor(256*Math.random())) + getHex(Math.floor(256*Math.random()));
      colorValues[i] = colorInput.value;
    }

    // Append elements to the div
    div.appendChild(label);
    div.appendChild(colorInput);
    div.appendChild(document.createElement('br'));
  }
}
setColorPickers(3);

let controls = {
  speed:0.3,
  dampening: 0.99997,
  loops:4,
  positions: [
    [(0.3+0.2*Math.random()),(0.5+0.2*Math.random())],
    [0.4,0.4],
    [0.6,0.39],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.3+0.4*Math.random()),(0.4+0.3*Math.random())],
    [(0.2+0.8*Math.random()),(0.1+0.8*Math.random())],
    [(0.2+0.8*Math.random()),(0.1+0.8*Math.random())],
    [(0.2+0.8*Math.random()),(0.1+0.8*Math.random())],
    [(0.2+0.8*Math.random()),(0.1+0.8*Math.random())],
  ],
  colors:[],
};

document.addEventListener('keydown', (event) => {
  // Check if the pressed key is space
  let res=-1;
  switch (event.key){
    case ' ': 
      event.preventDefault();
      pause=!pause;
      break;
    case 'ArrowUp':
      controls.loops += 2;
      worker.setLoops(controls.loops);
      break;
    case 'ArrowDown':
      if(controls.loops >= 3){
        controls.loops -= 2;
        worker.setLoops(controls.loops);
      }
      break;
    case 'PageUp':
      if(length < startBalls + pendingBalls + 1000){
        length = Math.round(1.2*length);
        console.log(worker);
        res = worker.setLength(length);
      }
      console.log("length = ", length, " res=", res);
      break;
    case 'PageDown':
      if(length > 200){
        length = Math.round(0.8*length);
        res = worker.setLength(length);
      }
      console.log("length = ", length, " res=", res);
      break;
    case 's':
      showShips=!showShips;
      worker.setShowShips(showShips);
      break;
  }
});

let lastPaint;

function startSimulation(){
  console.log("startSimulation! ", planetCount);
  document.getElementById('intro').style.display='none';
  document.body.style.backgroundColor='rgb(0,8,65)';
  planetCount    = document.getElementById('planetCount').value;
  canvasWidth    = document.getElementById('canvasWidth').value;
  canvasHeight   = document.getElementById('canvasHeight').value;
  for(let i=0; i<planetCount; i++){
    colorValues[i] = document.getElementById('color'+i).value;
  }
  startBalls = document.getElementById('startBalls').value;
  pendingBalls = document.getElementById('pendingBalls').value;
  length=Number(startBalls)+Number(pendingBalls);
  controls.speed = document.getElementById('gravity').value/100;
  controls.loops = Math.floor(document.getElementById('speed').value/10);
  console.log("controls = ", controls, " length=", length, " startBalls=", startBalls);
  setup();
}
function preparePaint(){
  ctx.putImageData(img, 0,0);
  ctx.fillStyle="#EFF0FF90";
}
function paintShip(x, y){
  // console.log("paintShip: ",x," ", y);
  // ctx.beginPath();
  //ctx.arc(x, y, 6, 0, 1.4*Math.PI);
  //ctx.stroke();
  //ctx.fill();
  ctx.fillRect(x-4,y-4,8,8);
}


function addResult(x, y, color){
  const red   = parseInt(colorValues[color].substr(1,2),16);
  const green = parseInt(colorValues[color].substr(3,2),16);
  const blue  = parseInt(colorValues[color].substr(5,2),16);
  if(UNIT<2){
    pos = 4*(y*canvasWidth + x);
    img.data[pos]  = red;
    img.data[pos+1]= green;
    img.data[pos+2]= blue;
    img.data[pos+3]=255;
    return;
  }
  const fromX = Math.max(0, Math.round(x-UNIT/2));
  const toX = Math.min(canvasWidth-1, Math.round(x+1+UNIT/2));
  const fromY = Math.max(0, Math.round(y-UNIT/2));
  const toY = Math.min(canvasHeight, Math.round(y+1+UNIT/2));
  var lx = fromX;
  var ly = fromY;
  while(ly < toY){
    pos = 4*(ly*canvasWidth + fromX);
    lx=fromX;
    while(lx<toX){
      img.data[pos]  = red;
      img.data[pos+1]= green;
      img.data[pos+2]= blue;
      img.data[pos+3]=255;
      pos += 4;
      lx++;
    }
    ly++;
  }
}

function finishPaint(){
  //console.log("finishPaint");
  for(let i=0; i<planetCount; i++){
    // console.log("paintShip: ",x," ", y);
    ctx.fillStyle=colorValues[i];
    ctx.strokeStyle=10;
    ctx.beginPath();
    ctx.arc(Math.round(canvasWidth*controls.positions[i][0]), Math.round(canvasHeight*controls.positions[i][1]), 9, 0, 1.9*Math.PI);
    ctx.stroke();
    ctx.fill();
  }
}
function finished(){
  console.log("finished!");
}

function debugBlock(pos, x, y){
  console.log("debugBlock: " , pos, " " , x, " " , y);
}
function setup() {

  console.log("setup!");
  var importObject = {
    env: {
      consoleLog: (arg) => console.log("cL", arg), // Useful for debugging on zig's side
      preparePaint: preparePaint,
      paintShip : paintShip,
      addResult : addResult,
      finishPaint: finishPaint,
      debugBlock: debugBlock,
      finished:finished,
    }
  };
  WebAssembly.instantiateStreaming(fetch("gravity.wasm"), importObject).then((result) => {
    console.log("gravity.wasm gave : ", result.instance);
    worker = result.instance.exports;
    console.log("start ", controls);
    // export fn init(width: usize, height: usize, blockSize: usize, lT, length, ength: usize, extra: usize, speed: f32, dampening: f32, memory: [*]u64) i8 {
    let res = worker.init(canvasWidth, canvasHeight, UNIT, length, pendingBalls, controls.speed, controls.dampening);
    console.log("worker init result: " , res);

    for(let planet=0; planet<planetCount; planet++){
      worker.addPlanet(Math.round(canvasWidth * controls.positions[planet][0]),Math.round(canvasHeight * controls.positions[planet][1]));
    }
    worker.setLoops(controls.loops);
  })
    .catch((e) => {console.log("no worker: ", e); worker = 1;});

  updatePosition();
  timer=setInterval(updatePosition, 10);
  let el = document.getElementById('renderCanvas');
  ctx=el.getContext("2d");
  ctx.canvas.width=canvasWidth;
  ctx.canvas.height=canvasHeight;
  img=ctx.createImageData(canvasWidth, canvasHeight);
  let pos=0;
  for (let y = 0; y < canvasHeight; y += 1) {
    for (let x = 0; x < canvasWidth; x += 1) {
      img.data[pos]  =  0;
      img.data[pos+1]= 8;
      img.data[pos+2]= 65;
      img.data[pos+3]=255;
      pos += 4;
    }
  }
  lastPaint=performance.now()-20;

  ctx.putImageData(img, 0,0);
  console.log("el = ", el, " img=", img, " context= ", ctx);
}

let steps=0;

function updatePosition(){
  if(! worker){
    console.log("no Worker ");
    if(worker == 1){
      return;
    }
    setTimeout(updatePosition, 10);
    return;
  }
  if(pause){
    return;
  }
  worker.updatePositions();
  const now = performance.now();
  if(now - lastPaint > 30){
    worker.paint();
    lastPaint = now;
  }

  return;
}

