;; WebAssembly Text Format (WAT) - 文本处理模块
;; 这是一个示例WASM模块，用于演示WebView可配置系统中的文本处理功能

(module
  ;; 导入内存
  (import "env" "memory" (memory 1))
  
  ;; 导入日志函数
  (import "env" "log" (func $log (param i32 i32)))
  
  ;; 导出函数：计算字符串长度
  (func $strlen (param $str i32) (result i32)
    (local $len i32)
    (local $char i32)
    
    i32.const 0
    local.set $len
    
    (loop $strLoop
      ;; 读取当前字符
      local.get $str
      local.get $len
      i32.add
      i32.load8_u
      local.set $char
      
      ;; 如果是空字符，结束循环
      local.get $char
      i32.eqz
      br_if 1
      
      ;; 长度加1
      local.get $len
      i32.const 1
      i32.add
      local.set $len
      
      br $strLoop
    )
    
    local.get $len
  )
  
  ;; 导出函数：字符串转大写
  (func $toUpperCase (param $str i32) (param $len i32) (result i32)
    (local $i i32)
    (local $char i32)
    
    i32.const 0
    local.set $i
    
    (loop $upperLoop
      ;; 检查是否处理完所有字符
      local.get $i
      local.get $len
      i32.ge_u
      br_if 1
      
      ;; 读取当前字符
      local.get $str
      local.get $i
      i32.add
      i32.load8_u
      local.set $char
      
      ;; 如果是小写字母 (a-z: 97-122)，转换为大写
      local.get $char
      i32.const 97
      i32.ge_u
      local.get $char
      i32.const 122
      i32.le_u
      i32.and
      if
        local.get $str
        local.get $i
        i32.add
        local.get $char
        i32.const 32
        i32.sub
        i32.store8
      end
      
      ;; 移动到下一个字符
      local.get $i
      i32.const 1
      i32.add
      local.set $i
      
      br $upperLoop
    )
    
    i32.const 1
  )
  
  ;; 导出函数：字符串转小写
  (func $toLowerCase (param $str i32) (param $len i32) (result i32)
    (local $i i32)
    (local $char i32)
    
    i32.const 0
    local.set $i
    
    (loop $lowerLoop
      local.get $i
      local.get $len
      i32.ge_u
      br_if 1
      
      ;; 读取当前字符
      local.get $str
      local.get $i
      i32.add
      i32.load8_u
      local.set $char
      
      ;; 如果是大写字母 (A-Z: 65-90)，转换为小写
      local.get $char
      i32.const 65
      i32.ge_u
      local.get $char
      i32.const 90
      i32.le_u
      i32.and
      if
        local.get $str
        local.get $i
        i32.add
        local.get $char
        i32.const 32
        i32.add
        i32.store8
      end
      
      local.get $i
      i32.const 1
      i32.add
      local.set $i
      
      br $lowerLoop
    )
    
    i32.const 1
  )
  
  ;; 导出函数：字符串反转
  (func $reverseString (param $str i32) (param $len i32) (result i32)
    (local $start i32)
    (local $end i32)
    (local $temp i32)
    
    i32.const 0
    local.set $start
    
    local.get $len
    i32.const 1
    i32.sub
    local.set $end
    
    (loop $reverseLoop
      ;; 如果start >= end，结束循环
      local.get $start
      local.get $end
      i32.ge_u
      br_if 1
      
      ;; 交换字符
      local.get $str
      local.get $start
      i32.add
      i32.load8_u
      local.set $temp
      
      local.get $str
      local.get $start
      i32.add
      local.get $str
      local.get $end
      i32.add
      i32.load8_u
      i32.store8
      
      local.get $str
      local.get $end
      i32.add
      local.get $temp
      i32.store8
      
      ;; 移动指针
      local.get $start
      i32.const 1
      i32.add
      local.set $start
      
      local.get $end
      i32.const 1
      i32.sub
      local.set $end
      
      br $reverseLoop
    )
    
    i32.const 1
  )
  
  ;; 导出函数：计算字符串哈希值 (简单的djb2算法)
  (func $hashString (param $str i32) (param $len i32) (result i32)
    (local $hash i32)
    (local $i i32)
    (local $char i32)
    
    i32.const 5381
    local.set $hash
    
    i32.const 0
    local.set $i
    
    (loop $hashLoop
      local.get $i
      local.get $len
      i32.ge_u
      br_if 1
      
      ;; 读取字符
      local.get $str
      local.get $i
      i32.add
      i32.load8_u
      local.set $char
      
      ;; hash = hash * 33 + char
      local.get $hash
      i32.const 33
      i32.mul
      local.get $char
      i32.add
      local.set $hash
      
      local.get $i
      i32.const 1
      i32.add
      local.set $i
      
      br $hashLoop
    )
    
    local.get $hash
  )
  
  ;; 导出函数：获取模块版本
  (func $getVersion (result i32)
    i32.const 101
  )
  
  ;; 导出所有函数
  (export "strlen" (func $strlen))
  (export "toUpperCase" (func $toUpperCase))
  (export "toLowerCase" (func $toLowerCase))
  (export "reverseString" (func $reverseString))
  (export "hashString" (func $hashString))
  (export "getVersion" (func $getVersion))
)