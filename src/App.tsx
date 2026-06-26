import { useState, useRef, useCallback, useEffect } from 'react'
import JSZip from 'jszip'
import './App.css'

interface Preset {
  label: string
  width: number
  height: number
}

interface ImageItem {
  name: string
  img: HTMLImageElement
}

const PRESETS: Preset[] = [
  { label: '1920×1080 (Full HD)', width: 1920, height: 1080 },
  { label: '2560×1440 (2K QHD)', width: 2560, height: 1440 },
  { label: '3840×2160 (4K UHD)', width: 3840, height: 2160 },
  { label: '3440×1440 (UltraWide)', width: 3440, height: 1440 },
  { label: '2560×1080 (UltraWide)', width: 2560, height: 1080 },
  { label: '5120×1440 (Super UW)', width: 5120, height: 1440 },
  { label: 'Custom', width: 0, height: 0 },
]

/** render a single wallpaper to a canvas, return the canvas */
function renderWallpaper(
  img: HTMLImageElement,
  outW: number,
  outH: number,
  blurRadius: number,
  bgMode: 'blur' | 'color',
  bgColor: string,
): HTMLCanvasElement {
  const canvas = document.createElement('canvas')
  canvas.width = outW
  canvas.height = outH
  const ctx = canvas.getContext('2d')!
  const iw = img.naturalWidth
  const ih = img.naturalHeight

  // background
  if (bgMode === 'blur') {
    const coverScale = Math.max(outW / iw, outH / ih)
    const bw = iw * coverScale
    const bh = ih * coverScale
    const bx = (outW - bw) / 2
    const by = (outH - bh) / 2

    const off = document.createElement('canvas')
    off.width = outW
    off.height = outH
    off.getContext('2d')!.drawImage(img, bx, by, bw, bh)

    ctx.filter = `blur(${blurRadius}px)`
    ctx.drawImage(off, 0, 0)
    ctx.filter = 'none'
  } else {
    ctx.fillStyle = bgColor
    ctx.fillRect(0, 0, outW, outH)
  }

  // foreground
  const fitScale = Math.min(outW / iw, outH / ih)
  const fw = iw * fitScale
  const fh = ih * fitScale
  const fx = (outW - fw) / 2
  const fy = (outH - fh) / 2
  ctx.drawImage(img, fx, fy, fw, fh)

  return canvas
}

function App() {
  const [images, setImages] = useState<ImageItem[]>([])
  const [selectedIndex, setSelectedIndex] = useState(0)
  const [presetIndex, setPresetIndex] = useState(0)
  const [customW, setCustomW] = useState(1920)
  const [customH, setCustomH] = useState(1080)
  const [blurRadius, setBlurRadius] = useState(30)
  const [bgMode, setBgMode] = useState<'blur' | 'color'>('blur')
  const [bgColor, setBgColor] = useState('#0d0d0d')
  const [isDragover, setIsDragover] = useState(false)
  const [generating, setGenerating] = useState(false)

  const previewCanvasRef = useRef<HTMLCanvasElement>(null)

  const pres = PRESETS[presetIndex]
  const outW = pres.width > 0 ? pres.width : customW
  const outH = pres.height > 0 ? pres.height : customH

  const selected = images[selectedIndex] ?? null

  // --- load images from files ---
  const loadFiles = useCallback((files: FileList | File[]) => {
    const valid = Array.from(files).filter((f) => f.type.startsWith('image/'))
    if (valid.length === 0) return

    Promise.all(
      valid.map(
        (file) =>
          new Promise<ImageItem>((resolve) => {
            const reader = new FileReader()
            reader.onload = () => {
              const img = new Image()
              img.onload = () => resolve({ name: file.name, img })
              img.src = reader.result as string
            }
            reader.readAsDataURL(file)
          }),
      ),
    ).then((newImages) => {
      setImages((prev) => [...prev, ...newImages])
    })
  }, [])

  // --- drag & drop handlers ---
  const onDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragover(true)
  }, [])
  const onDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragover(false)
  }, [])
  const onDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault()
      setIsDragover(false)
      if (e.dataTransfer.files.length > 0) loadFiles(e.dataTransfer.files)
    },
    [loadFiles],
  )
  const onFileChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      if (e.target.files && e.target.files.length > 0) loadFiles(e.target.files)
      // reset so same file(s) can be re-selected
      e.target.value = ''
    },
    [loadFiles],
  )

  const removeImage = useCallback(
    (i: number) => {
      setImages((prev) => prev.filter((_, idx) => idx !== i))
      setSelectedIndex((prev) => {
        if (i < prev) return prev - 1
        if (i === prev && prev > 0) return prev - 1
        return Math.min(prev, images.length - 2)
      })
    },
    [images.length],
  )

  const clearAll = useCallback(() => {
    setImages([])
    setSelectedIndex(0)
  }, [])

  // --- preview canvas ---
  useEffect(() => {
    const canvas = previewCanvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const dpr = window.devicePixelRatio || 1
    const previewMaxW = 600
    const scale = Math.min(1, previewMaxW / outW)
    const displayW = Math.round(outW * scale)
    const displayH = Math.round(outH * scale)

    canvas.width = displayW * dpr
    canvas.height = displayH * dpr
    canvas.style.width = `${displayW}px`
    canvas.style.height = `${displayH}px`
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

    ctx.fillStyle = '#000'
    ctx.fillRect(0, 0, displayW, displayH)

    if (!selected) return

    const result = renderWallpaper(selected.img, outW, outH, blurRadius, bgMode, bgColor)
    ctx.drawImage(result, 0, 0, displayW, displayH)
  }, [selected, outW, outH, blurRadius, bgMode, bgColor])

  // --- download single ---
  const downloadSingle = useCallback(
    (item: ImageItem) => {
      const result = renderWallpaper(item.img, outW, outH, blurRadius, bgMode, bgColor)
      result.toBlob((blob) => {
        if (!blob) return
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        const base = item.name.replace(/\.[^.]+$/, '')
        a.download = `${base}_wallpaper_${outW}x${outH}.png`
        a.click()
        URL.revokeObjectURL(url)
      }, 'image/png')
    },
    [outW, outH, blurRadius, bgMode, bgColor],
  )

  // --- download all as zip ---
  const downloadAll = useCallback(async () => {
    if (images.length === 0) return
    setGenerating(true)
    try {
      const zip = new JSZip()
      for (const item of images) {
        const result = renderWallpaper(item.img, outW, outH, blurRadius, bgMode, bgColor)
        const blob = await new Promise<Blob>((resolve) =>
          result.toBlob((b) => resolve(b!), 'image/png'),
        )
        const base = item.name.replace(/\.[^.]+$/, '')
        zip.file(`${base}_wallpaper_${outW}x${outH}.png`, blob)
      }
      const zipBlob = await zip.generateAsync({ type: 'blob' })
      const url = URL.createObjectURL(zipBlob)
      const a = document.createElement('a')
      a.href = url
      a.download = `wallpapers_${outW}x${outH}.zip`
      a.click()
      URL.revokeObjectURL(url)
    } finally {
      setGenerating(false)
    }
  }, [images, outW, outH, blurRadius, bgMode, bgColor])

  return (
    <div className="app">
      <header className="header">
        <h1>🖼️ 壁纸制作器</h1>
        <p className="subtitle">竖屏照片 → 桌面壁纸，不裁剪，模糊填充背景 — 支持批量</p>
      </header>

      <main className="main">
        {/* left: controls */}
        <aside className="controls">
          {/* upload */}
          <div
            className={`dropzone ${isDragover ? 'dragover' : ''} ${images.length > 0 ? 'has-image' : ''}`}
            onDragOver={onDragOver}
            onDragLeave={onDragLeave}
            onDrop={onDrop}
            onClick={() => document.getElementById('fileInput')?.click()}
          >
            <div className="drop-info">
              <span className="drop-icon">
                {images.length > 0 ? '✅' : '📁'}
              </span>
              <span className="drop-text">
                {images.length > 0
                  ? `已选 ${images.length} 张图片`
                  : '拖拽图片到这里'}
              </span>
              <span className="drop-hint">
                {images.length > 0 ? '点击或拖拽继续添加' : '或点击选择文件（可多选）'}
              </span>
            </div>
            <input
              id="fileInput"
              type="file"
              accept="image/*"
              multiple
              onChange={onFileChange}
              hidden
            />
          </div>

          {/* image list */}
          {images.length > 0 && (
            <div className="control-group">
              <div className="image-list-header">
                <label className="control-label">
                  图片列表 ({images.length})
                </label>
                <button className="clear-btn" onClick={clearAll}>
                  清空
                </button>
              </div>
              <div className="image-list">
                {images.map((item, i) => (
                  <div
                    key={i}
                    className={`image-list-item ${i === selectedIndex ? 'selected' : ''}`}
                    onClick={() => setSelectedIndex(i)}
                  >
                    <img
                      src={item.img.src}
                      alt={item.name}
                      className="list-thumb"
                    />
                    <span className="list-name" title={item.name}>
                      {item.name}
                    </span>
                    <button
                      className="list-remove"
                      onClick={(e) => {
                        e.stopPropagation()
                        removeImage(i)
                      }}
                      title="移除"
                    >
                      ✕
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* resolution */}
          <div className="control-group">
            <label className="control-label">目标分辨率</label>
            <select
              className="select"
              value={presetIndex}
              onChange={(e) => setPresetIndex(Number(e.target.value))}
            >
              {PRESETS.map((p, i) => (
                <option key={i} value={i}>
                  {p.label}
                </option>
              ))}
            </select>
            {presetIndex === PRESETS.length - 1 && (
              <div className="custom-size">
                <input
                  type="number"
                  className="input size-input"
                  value={customW}
                  onChange={(e) => setCustomW(Number(e.target.value))}
                  placeholder="宽"
                />
                <span>×</span>
                <input
                  type="number"
                  className="input size-input"
                  value={customH}
                  onChange={(e) => setCustomH(Number(e.target.value))}
                  placeholder="高"
                />
              </div>
            )}
          </div>

          {/* background mode */}
          <div className="control-group">
            <label className="control-label">背景模式</label>
            <div className="radio-group">
              <label className={`radio ${bgMode === 'blur' ? 'active' : ''}`}>
                <input
                  type="radio"
                  name="bgMode"
                  value="blur"
                  checked={bgMode === 'blur'}
                  onChange={() => setBgMode('blur')}
                />
                模糊填充
              </label>
              <label className={`radio ${bgMode === 'color' ? 'active' : ''}`}>
                <input
                  type="radio"
                  name="bgMode"
                  value="color"
                  checked={bgMode === 'color'}
                  onChange={() => setBgMode('color')}
                />
                纯色背景
              </label>
            </div>
          </div>

          {bgMode === 'blur' && (
            <div className="control-group">
              <label className="control-label">
                模糊强度: <strong>{blurRadius}px</strong>
              </label>
              <input
                type="range"
                className="slider"
                min={5}
                max={80}
                value={blurRadius}
                onChange={(e) => setBlurRadius(Number(e.target.value))}
              />
            </div>
          )}

          {bgMode === 'color' && (
            <div className="control-group">
              <label className="control-label">背景颜色</label>
              <input
                type="color"
                className="color-input"
                value={bgColor}
                onChange={(e) => setBgColor(e.target.value)}
              />
            </div>
          )}

          {/* download buttons */}
          {images.length > 0 && (
            <div className="download-group">
              <button
                className="download-btn primary"
                disabled={generating}
                onClick={downloadAll}
              >
                {generating
                  ? '⏳ 打包中...'
                  : `⬇ 下载全部 (${images.length} 张 → ZIP)`}
              </button>
              {selected && (
                <button
                  className="download-btn secondary"
                  onClick={() => downloadSingle(selected)}
                >
                  仅下载当前 ({selected.name})
                </button>
              )}
            </div>
          )}
        </aside>

        {/* right: preview */}
        <section className="preview">
          <div className="preview-label">
            预览 — {outW}×{outH}
            {selected && ` — ${selected.name}`}
          </div>
          <div className="preview-box">
            {selected ? (
              <canvas ref={previewCanvasRef} className="preview-canvas" />
            ) : (
              <div className="preview-placeholder">
                <span className="placeholder-icon">🖼️</span>
                <span>
                  {images.length > 0
                    ? '点击左侧列表选择图片预览'
                    : '上传图片后在此预览'}
                </span>
              </div>
            )}
          </div>
        </section>
      </main>
    </div>
  )
}

export default App
