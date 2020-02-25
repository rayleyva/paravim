import nimgl/opengl
from nimgl/glfw import GLFWKey
import paranim/gl, paranim/gl/entities
from paranim/primitives import nil
from paranim/math as pmath import translate
import pararules
from text import nil
from buffers import BufferUpdateTuple
import sets
from math import `mod`
from glm import nil

const
  bgColor = glm.vec4(GLfloat(52/255), GLfloat(40/255), GLfloat(42/255), GLfloat(0.95))
  textColor = glm.vec4(1f, 1f, 1f, 1f)
  cursorColor = glm.vec4(GLfloat(112/255), GLfloat(128/255), GLfloat(144/255), GLfloat(0.9))

type
  Id* = enum
    Global
  Attr* = enum
    WindowWidth, WindowHeight,
    MouseClick, MouseX, MouseY,
    FontSize, CurrentBufferId, BufferUpdate,
    BufferId, Lines, Path,
    CursorLine, CursorColumn, ScrollX, ScrollY,
  Strings = seq[string]

schema Fact(Id, Attr):
  WindowWidth: int
  WindowHeight: int
  MouseClick: int
  MouseX: float
  MouseY: float
  FontSize: float
  CurrentBufferId: int
  BufferUpdate: BufferUpdateTuple
  BufferId: int
  Lines: Strings
  Path: string
  CursorLine: int
  CursorColumn: int
  ScrollX: float
  ScrollY: float

let rules =
  ruleset:
    rule getWindow(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Global, WindowHeight, windowHeight)
    rule getFont(Fact):
      what:
        (Global, FontSize, fontSize)
    rule getCurrentBuffer(Fact):
      what:
        (Global, CurrentBufferId, cb)
        (id, BufferId, cb)
        (id, Lines, lines)
        (id, CursorLine, cursorLine)
        (id, CursorColumn, cursorColumn)
        (id, ScrollX, scrollX)
        (id, ScrollY, scrollY)
    rule getBuffer(Fact):
      what:
        (id, BufferId, bufferId)
    rule onBufferUpdate(Fact):
      what:
        (Global, BufferUpdate, bu)
        (id, Lines, lines)
        (id, BufferId, bufferId)
      cond:
        bufferId == bu.bufferId
      then:
        session.retract(Global, BufferUpdate, bu)
        session.insert(id, Lines, buffers.updateLines(lines, bu))
    rule updateScrollX(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Global, FontSize, fontSize)
        (id, CursorColumn, cursorColumn)
        (id, ScrollX, scrollX, then = false)
      then:
        let
          fontWidth = text.monoFont.chars[0].xadvance * fontSize
          cursorLeft = cursorColumn.float * fontWidth
          cursorRight = cursorLeft + fontWidth
          textWidth = windowWidth.float
          scrollRight = scrollX + textWidth
        if cursorLeft < scrollX:
          session.insert(id, ScrollX, cursorLeft)
        elif cursorRight > scrollRight:
          session.insert(id, ScrollX, cursorRight - textWidth)
    rule updateScrollY(Fact):
      what:
        (Global, WindowHeight, windowHeight)
        (Global, FontSize, fontSize)
        (id, CursorLine, cursorLine)
        (id, ScrollY, scrollY, then = false)
      then:
        let
          fontHeight = text.monoFont.height * fontSize
          cursorTop = cursorLine.float * fontHeight
          cursorBottom = cursorTop + fontHeight
          textHeight = windowHeight.float
          scrollBottom = scrollY + textHeight
        if cursorTop < scrollY:
          session.insert(id, ScrollY, cursorTop)
        elif cursorBottom > scrollBottom and scrollBottom > 0:
          session.insert(id, ScrollY, cursorBottom - textHeight)

var
  session* = initSession(Fact)
  nextId* = Id.high.ord + 1
  cursorEntity: TwoDEntity

proc getCurrentSessionId*(): int =
  let index = session.find(rules.getCurrentBuffer)
  if index >= 0:
    session.get(rules.getCurrentBuffer, index).id
  else:
    -1

proc getSessionId*(bufferId: int): int =
  let index = session.find(rules.getBuffer, bufferId = bufferId)
  if index >= 0:
    session.get(rules.getBuffer, index).id
  else:
    -1

for r in rules.fields:
  session.add(r)

proc mouseClicked*(button: int) =
  session.insert(Global, MouseClick, button)

proc mouseMoved*(xpos: float, ypos: float) =
  session.insert(Global, MouseX, xpos)
  session.insert(Global, MouseY, ypos)

proc windowResized*(width: int, height: int) =
  if width == 0 or height == 0:
    return
  session.insert(Global, WindowWidth, width)
  session.insert(Global, WindowHeight, height)

proc init*(game: var RootGame) =
  # opengl
  doAssert glInit()
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

  # init fonts
  text.init(game)

  # init cursor
  cursorEntity = compile(game, initTwoDEntity(primitives.rectangle[GLfloat]()))

  # set initial values
  session.insert(Global, FontSize, 1/4)

proc tick*(game: RootGame) =
  let (windowWidth, windowHeight) = session.query(rules.getWindow)
  let (fontSize) = session.query(rules.getFont)
  let currentBufferIndex = session.find(rules.getCurrentBuffer)

  glClearColor(bgColor.arr[0], bgColor.arr[1], bgColor.arr[2], bgColor.arr[3])
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, int32(windowWidth), int32(windowHeight))

  if currentBufferIndex >= 0:
    let currentBuffer = session.get(rules.getCurrentBuffer, currentBufferIndex)
    var camera = glm.mat3f(1)
    camera.translate(currentBuffer.scrollX, currentBuffer.scrollY)

    block:
      let fontWidth = text.monoFont.chars[0].xadvance
      var e = cursorEntity
      e.project(float(windowWidth), float(windowHeight))
      e.invert(camera)
      e.scale(fontWidth * fontSize, text.monoFont.height * fontSize)
      e.translate(currentBuffer.cursorColumn.GLfloat, currentBuffer.cursorLine.GLfloat)
      e.color(cursorColor)
      render(game, e)

    block:
      var e = deepCopy(text.monoEntity)
      for i in 0 ..< currentBuffer.lines.len:
        text.addLine(e, text.baseMonoEntity, text.monoFont, textColor, currentBuffer.lines[i])
      e.project(float(windowWidth), float(windowHeight))
      e.invert(camera)
      e.scale(fontSize, fontSize)
      render(game, e)
