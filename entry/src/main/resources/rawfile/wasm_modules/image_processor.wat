;; WebAssembly Text Format (WAT) - 图像处理模块
;; 这是一个示例WASM模块，用于演示WebView可配置系统中的WASM功能

(module
  ;; 导入内存
  (import "env" "memory" (memory 1))
  
  ;; 导入日志函数
  (import "env" "log" (func $log (param i32 i32)))
  
  ;; 导出函数：图像亮度调整
  (func $adjustBrightness (param $imageData i32) (param $width i32) (param $height i32) (param $brightness f32) (result i32)
    (local $i i32)
    (local $pixelCount i32)
    (local $r i32)
    (local $g i32)
    (local $b i32)
    (local $newR f32)
    (local $newG f32)
    (local $newB f32)
    
    ;; 计算像素总数 (width * height * 4 for RGBA)
    local.get $width
    local.get $height
    i32.mul
    i32.const 4
    i32.mul
    local.set $pixelCount
    
    ;; 循环处理每个像素
    i32.const 0
    local.set $i
    
    (loop $pixelLoop
      ;; 检查是否处理完所有像素
      local.get $i
      local.get $pixelCount
      i32.ge_u
      br_if 1
      
      ;; 读取RGB值 (跳过Alpha通道)
      local.get $imageData
      local.get $i
      i32.add
      i32.load8_u
      local.set $r
      
      local.get $imageData
      local.get $i
      i32.const 1
      i32.add
      i32.add
      i32.load8_u
      local.set $g
      
      local.get $imageData
      local.get $i
      i32.const 2
      i32.add
      i32.add
      i32.load8_u
      local.set $b
      
      ;; 应用亮度调整
      local.get $r
      f32.convert_i32_u
      local.get $brightness
      f32.mul
      local.set $newR
      
      local.get $g
      f32.convert_i32_u
      local.get $brightness
      f32.mul
      local.set $newG
      
      local.get $b
      f32.convert_i32_u
      local.get $brightness
      f32.mul
      local.set $newB
      
      ;; 限制值在0-255范围内
      local.get $newR
      f32.const 255.0
      f32.min
      f32.const 0.0
      f32.max
      i32.trunc_f32_u
      local.set $r
      
      local.get $newG
      f32.const 255.0
      f32.min
      f32.const 0.0
      f32.max
      i32.trunc_f32_u
      local.set $g
      
      local.get $newB
      f32.const 255.0
      f32.min
      f32.const 0.0
      f32.max
      i32.trunc_f32_u
      local.set $b
      
      ;; 写回调整后的RGB值
      local.get $imageData
      local.get $i
      i32.add
      local.get $r
      i32.store8
      
      local.get $imageData
      local.get $i
      i32.const 1
      i32.add
      i32.add
      local.get $g
      i32.store8
      
      local.get $imageData
      local.get $i
      i32.const 2
      i32.add
      i32.add
      local.get $b
      i32.store8
      
      ;; 移动到下一个像素 (跳过4个字节: RGBA)
      local.get $i
      i32.const 4
      i32.add
      local.set $i
      
      br $pixelLoop
    )
    
    ;; 返回成功状态
    i32.const 1
  )
  
  ;; 导出函数：图像对比度调整
  (func $adjustContrast (param $imageData i32) (param $width i32) (param $height i32) (param $contrast f32) (result i32)
    (local $i i32)
    (local $pixelCount i32)
    (local $r i32)
    (local $g i32)
    (local $b i32)
    (local $newR f32)
    (local $newG f32)
    (local $newB f32)
    (local $factor f32)
    
    ;; 计算对比度因子
    local.get $contrast
    f32.const 1.0
    f32.add
    f32.const 259.0
    f32.mul
    local.get $contrast
    f32.const 255.0
    f32.mul
    f32.const 259.0
    f32.add
    f32.div
    local.set $factor
    
    ;; 计算像素总数
    local.get $width
    local.get $height
    i32.mul
    i32.const 4
    i32.mul
    local.set $pixelCount
    
    ;; 循环处理每个像素
    i32.const 0
    local.set $i
    
    (loop $contrastLoop
      local.get $i
      local.get $pixelCount
      i32.ge_u
      br_if 1
      
      ;; 读取RGB值
      local.get $imageData
      local.get $i
      i32.add
      i32.load8_u
      local.set $r
      
      local.get $imageData
      local.get $i
      i32.const 1
      i32.add
      i32.add
      i32.load8_u
      local.set $g
      
      local.get $imageData
      local.get $i
      i32.const 2
      i32.add
      i32.add
      i32.load8_u
      local.set $b
      
      ;; 应用对比度调整
      local.get $factor
      local.get $r
      f32.convert_i32_u
      f32.const 128.0
      f32.sub
      f32.mul
      f32.const 128.0
      f32.add
      local.set $newR
      
      local.get $factor
      local.get $g
      f32.convert_i32_u
      f32.const 128.0
      f32.sub
      f32.mul
      f32.const 128.0
      f32.add
      local.set $newG
      
      local.get $factor
      local.get $b
      f32.convert_i32_u
      f32.const 128.0
      f32.sub
      f32.mul
      f32.const 128.0
      f32.add
      local.set $newB
      
      ;; 限制值在0-255范围内并写回
      local.get $imageData
      local.get $i
      i32.add
      local.get $newR
      f32.const 255.0
      f32.min
      f32.const 0.0
      f32.max
      i32.trunc_f32_u
      i32.store8
      
      local.get $imageData
      local.get $i
      i32.const 1
      i32.add
      i32.add
      local.get $newG
      f32.const 255.0
      f32.min
      f32.const 0.0
      f32.max
      i32.trunc_f32_u
      i32.store8
      
      local.get $imageData
      local.get $i
      i32.const 2
      i32.add
      i32.add
      local.get $newB
      f32.const 255.0
      f32.min
      f32.const 0.0
      f32.max
      i32.trunc_f32_u
      i32.store8
      
      ;; 移动到下一个像素
      local.get $i
      i32.const 4
      i32.add
      local.set $i
      
      br $contrastLoop
    )
    
    i32.const 1
  )
  
  ;; 导出函数：获取模块信息
  (func $getModuleInfo (result i32)
    ;; 返回模块版本号
    i32.const 100
  )
  
  ;; 导出所有函数
  (export "adjustBrightness" (func $adjustBrightness))
  (export "adjustContrast" (func $adjustContrast))
  (export "getModuleInfo" (func $getModuleInfo))
)