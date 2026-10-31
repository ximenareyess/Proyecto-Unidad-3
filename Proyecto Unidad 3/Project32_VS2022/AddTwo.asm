
; Proyecto Unidad 3 - Ventas e inventario 
; Negocio : Papeleria
;         : DESCUENTO POR CANTIDAD -> si se venden 10 o mas unidades de un
;           producto, se descuenta el 10% del importe base. La fraccion de
;           centavo se descarta (division entera).





INCLUDE Irvine32.inc

PROD_MAX     EQU 10
REC_SIZE     EQU 44            ; tamaño de cada registro de producto
OFF_CODE     EQU 0             ; 8 bytes  : "ABC-123",0
OFF_NAME     EQU 8             ; 26 bytes : nombre (1..25) + 0
OFF_PRICE    EQU 36            ; DWORD    : centavos (1..999999)
OFF_STOCK    EQU 40            ; DWORD    : existencia (0..100)
CODE_SIZE    EQU 8
NAME_SIZE    EQU 26
FILE_CAP     EQU 2048                    ; capacidad de lectura (el archivo valido mide < 500)
INBUF_MAX    EQU 63
MAX_PRICE    EQU 999999
MAX_STOCK    EQU 100
DISC_MIN_QTY EQU 10
DISC_PCT     EQU 10

; Muestra una cadena constante (preserva EDX)
Say MACRO txt
    push edx
    mov  edx, OFFSET txt
    call WriteString
    pop  edx
ENDM

.data
prodCount   DWORD 0                           ; numero de productos
products    BYTE  PROD_MAX*REC_SIZE DUP(0)    ; tabla de registros
tmpTable    BYTE  PROD_MAX*REC_SIZE DUP(0)    ; tabla temporal para validar al cargar
tmpCount    DWORD 0
curRec      DWORD ?
fieldbuf    BYTE  32 DUP(0)
outbuf      BYTE  600 DUP(0)                  ; texto que se escribe al archivo
txtHeader   BYTE  "INV1",13,10,0
txtSemi     BYTE  ";",0
txtCRLF     BYTE  13,10,0
revenue     DWORD 0              ; ingresos de la sesion (centavos)
dirty       BYTE  0              ; 1 = cambios sin guardar
mainEsp     DWORD ?              ; ESP de referencia para verificar la pila

inbuf       BYTE  INBUF_MAX+1 DUP(0)
junkbuf     BYTE  INBUF_MAX+1 DUP(0)
tmpCode     BYTE  CODE_SIZE DUP(0)
tmpName     BYTE  NAME_SIZE DUP(0)
tmpPrice    DWORD ?
tmpStock    DWORD ?
numbuf      BYTE  12 DUP(0)

fileName    BYTE  "inventario.dat",0
hFile       DWORD ?
expected    DWORD ?
bytesRead   DWORD ?
loadbuf     BYTE  FILE_CAP+1 DUP(0)     ; +1 para el terminador 00h

msgBanner   BYTE  13,10,"=== PAPELERIA - Ventas e inventario ===",13,10,0
msgMenu     BYTE  13,10,"1) Registrar producto   2) Mostrar inventario  3) Buscar por codigo",13,10
            BYTE  "4) Recibir mercancia    5) Vender              6) Resumen",13,10
            BYTE  "7) Guardar              8) Cargar              9) Salir",13,10
            BYTE  "Opcion: ",0
msgBadOpt   BYTE  "Opcion invalida.",13,10,0
msgBadInput BYTE  "Entrada vacia o demasiado larga. Operacion rechazada.",13,10,0
msgAskCode  BYTE  "Codigo (ABC-123): ",0
msgAskName  BYTE  "Nombre (1 a 25 caracteres): ",0
msgAskPrice BYTE  "Precio en MXN (ej. 185.50): ",0
msgAskStock BYTE  "Existencia inicial (0 a 100): ",0
msgAskQty   BYTE  "Cantidad (1 a 100): ",0
msgBadCode  BYTE  "Codigo invalido (formato ABC-123). Operacion rechazada.",13,10,0
msgDup      BYTE  "Codigo duplicado. Operacion rechazada.",13,10,0
msgNotFound BYTE  "Producto no encontrado.",13,10,0
msgBadName  BYTE  "Nombre invalido. Operacion rechazada.",13,10,0
msgBadPrice BYTE  "Precio invalido (0.01 a 9999.99, sin simbolos). Operacion rechazada.",13,10,0
msgBadStock BYTE  "Existencia invalida. Operacion rechazada.",13,10,0
msgBadQty   BYTE  "Cantidad invalida. Operacion rechazada.",13,10,0
msgFull     BYTE  "Capacidad llena (10 productos). Operacion rechazada.",13,10,0
msgRegOk    BYTE  "Producto registrado.",13,10,0
msgEmpty    BYTE  "Inventario vacio.",13,10,0
msgExcess   BYTE  "La existencia excederia 100 unidades. Operacion rechazada.",13,10,0
msgRecvOk   BYTE  "Mercancia recibida. Existencia actual: ",0
msgNoStock  BYTE  "Existencias insuficientes. Venta rechazada.",13,10,0
msgOvf      BYTE  "Desbordamiento detectado. Operacion rechazada.",13,10,0
msgBase     BYTE  "Importe base : ",0
msgDisc     BYTE  "Descuento 10% por cantidad (>=10 uds): -",0
msgNoDisc   BYTE  "Sin descuento (menos de 10 unidades).",13,10,0
msgFinal    BYTE  "Importe final: ",0
msgSaleOk   BYTE  "Venta aceptada.",13,10,0
msgSumUnits BYTE  "Unidades disponibles : ",0
msgSumValue BYTE  "Valor del inventario : ",0
msgSumRev   BYTE  "Ingresos de sesion   : ",0
msgSaved    BYTE  "Catalogo guardado en inventario.dat.",13,10,0
msgSaveErr  BYTE  "Error al guardar el archivo.",13,10,0
msgNoFile   BYTE  "No existe inventario.dat (o no se pudo abrir). Catalogo actual conservado.",13,10,0
msgReadErr  BYTE  "Error de lectura del archivo. Catalogo actual conservado.",13,10,0
msgInvalid  BYTE  "Archivo danado o con formato invalido. Catalogo actual conservado.",13,10,0
msgLoaded   BYTE  "Catalogo cargado correctamente.",13,10,0
msgUnsaved  BYTE  "Hay cambios sin guardar. Continuar de todos modos? (S/N): ",0
msgStackErr BYTE  "ERROR: pila desbalanceada.",13,10,0
msgSep      BYTE  " | ",0
msgExist    BYTE  " | Existencia: ",0
msgDollar   BYTE  "$",0
msgDot      BYTE  ".",0
msgZero     BYTE  "0",0
msgMXN      BYTE  " MXN",0

.code

; CopyPad : copia una cadena a un campo de tamano fijo y rellena con 0.
; Entrada : ESI = origen (cadena terminada en 0), EDI = destino, ECX = tamano
;           del campo (incluye el 0 final).
; Salida  : campo con a lo mas ECX-1 caracteres + ceros.

CopyPad PROC
    push eax
    push ecx
    push esi
    push edi
    dec  ecx                    ; reserva el byte del terminador
cp_loop:
    test ecx, ecx
    jz   cp_fin
    mov  al, [esi]
    test al, al
    jz   cp_fin
    mov  [edi], al
    inc  esi
    inc  edi
    dec  ecx
    jmp  cp_loop
cp_fin:
    inc  ecx                    ; bytes restantes (>=1) a poner en cero
cp_zero:
    mov  BYTE PTR [edi], 0
    inc  edi
    dec  ecx
    jnz  cp_zero
    pop  edi
    pop  esi
    pop  ecx
    pop  eax
    ret
CopyPad ENDP


; ReadLine : captura una linea en inbuf con ReadString.
; Entrada : (ninguna) EDX=OFFSET inbuf y ECX=INBUF_MAX se preparan aqui.
; Salida  : EAX = caracteres leidos; CF=1 si la linea era demasiado larga
;           (el resto se descarta leyendo hasta vaciar la linea).

ReadLine PROC
    push edx
    push ecx
    mov  edx, OFFSET inbuf
    mov  ecx, INBUF_MAX         ; max de caracteres (buffer = ECX+1 bytes)
    call ReadString             ; EAX = numero de caracteres capturados
    cmp  eax, INBUF_MAX
    jb   rl_ok
rl_drain:
    mov  edx, OFFSET junkbuf
    mov  ecx, INBUF_MAX
    call ReadString
    cmp  eax, INBUF_MAX
    jae  rl_drain
    mov  eax, INBUF_MAX
    stc
    jmp  rl_done
rl_ok:
    clc
rl_done:
    pop  ecx
    pop  edx
    ret
ReadLine ENDP


; GetInput : ReadLine + rechazo de entrada vacia o demasiado larga.
; Salida  : EAX = longitud; CF=1 si hay error (ya muestra el mensaje).
; Modifica: EAX, EFLAGS

GetInput PROC
    call ReadLine
    jc   gi_bad
    test eax, eax
    jnz  gi_ok
gi_bad:
    Say  msgBadInput
    stc
    ret
gi_ok:
    clc
    ret
GetInput ENDP


; ParseUInt : cadena de digitos -> entero sin signo (solo '0'..'9').
; Entrada : ESI = cadena terminada en 0.
; Salida  : EAX = valor; CF=1 si vacia, con caracteres no permitidos o si
;           desborda 32 bits.

ParseUInt PROC
    push ebx
    push ecx
    push edx
    push esi
    xor  eax, eax
    xor  ecx, ecx               ; contador de digitos
pu_loop:
    movzx ebx, BYTE PTR [esi]
    test bl, bl
    jz   pu_end
    cmp  bl, '0'
    jb   pu_bad
    cmp  bl, '9'
    ja   pu_bad
    sub  ebx, '0'
    mov  edx, 10
    mul  edx                    ; EDX:EAX = EAX*10 ; CF=1 si EDX<>0
    jc   pu_bad
    add  eax, ebx
    jc   pu_bad
    inc  esi
    inc  ecx
    jmp  pu_loop
pu_end:
    test ecx, ecx
    jz   pu_bad
    clc
    jmp  pu_done
pu_bad:
    stc
pu_done:
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
ParseUInt ENDP

; ParsePrice : "185.50" -> 18550 centavos. Acepta enteros o punto con 1 o 2
;              decimales. Rechaza simbolos, separadores de miles, ".5", "5.",
;              tercer decimal y fuera de rango (1..999999 centavos).
; Entrada : ESI = cadena terminada en 0.
; Salida  : EAX = centavos; CF=1 si es invalida.

ParsePrice PROC
    push ebx
    push ecx
    push edx
    push esi
    xor  eax, eax               ; pesos
    xor  ecx, ecx               ; digitos enteros
pp_int:
    movzx edx, BYTE PTR [esi]
    test dl, dl
    jz   pp_intEnd
    cmp  dl, '.'
    je   pp_intEnd
    cmp  dl, '0'
    jb   pp_bad
    cmp  dl, '9'
    ja   pp_bad
    sub  edx, '0'
    imul eax, eax, 10
    add  eax, edx
    cmp  eax, 9999              ; evita desbordar y valida el maximo de pesos
    ja   pp_bad
    inc  esi
    inc  ecx
    jmp  pp_int
pp_intEnd:
    test ecx, ecx               ; al menos un digito antes del punto
    jz   pp_bad
    imul ebx, eax, 100          ; EBX = pesos*100
    cmp  BYTE PTR [esi], 0
    je   pp_range               ; sin parte decimal
    inc  esi                    ; salta el '.'
    movzx edx, BYTE PTR [esi]   ; primer decimal (obligatorio)
    cmp  dl, '0'
    jb   pp_bad
    cmp  dl, '9'
    ja   pp_bad
    sub  edx, '0'
    imul edx, edx, 10           ; decenas de centavo
    add  ebx, edx
    inc  esi
    cmp  BYTE PTR [esi], 0
    je   pp_range               ; un solo decimal: 185.5 -> 18550
    movzx edx, BYTE PTR [esi]   ; segundo decimal
    cmp  dl, '0'
    jb   pp_bad
    cmp  dl, '9'
    ja   pp_bad
    sub  edx, '0'
    add  ebx, edx
    inc  esi
    cmp  BYTE PTR [esi], 0      ; un tercer caracter => rechazo
    jne  pp_bad
pp_range:
    cmp  ebx, 1
    jb   pp_bad
    cmp  ebx, MAX_PRICE
    ja   pp_bad
    mov  eax, ebx
    clc
    jmp  pp_done
pp_bad:
    stc
pp_done:
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
ParsePrice ENDP


; PrintU32 : muestra EAX como decimal sin signo (division entre 10).
;            Los digitos salen en orden inverso (residuos), por eso se
;            escriben desde el final del buffer hacia atras.
; Entrada : EAX = valor.
; Salida  : texto en consola.

PrintU32 PROC
    push eax
    push ebx
    push ecx
    push edx
    push edi
    mov  edi, OFFSET numbuf + 11
    mov  BYTE PTR [edi], 0      ; terminador 00h
    mov  ebx, 10
pu32_loop:
    xor  edx, edx               ; dividendo = EDX:EAX
    div  ebx                    ; EAX = cociente, EDX = residuo (0..9)
    add  dl, '0'                ; digito.. ASCII
    dec  edi
    mov  [edi], dl
    test eax, eax
    jnz  pu32_loop
    mov  edx, edi
    call WriteString
    pop  edi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret
PrintU32 ENDP


; PrintMXN : muestra centavos como "$ 1234.05 MXN".
; Entrada : EAX = centavos.
; Salida  : texto en consola.

PrintMXN PROC
    push eax
    push ebx
    push edx
    Say  msgDollar
    mov  ebx, 100
    xor  edx, edx
    div  ebx                    ; EAX = pesos, EDX = centavos (0..99)
    push edx                    ; guarda centavos
    call PrintU32               ; pesos
    Say  msgDot
    pop  eax                    ; centavos
    cmp  eax, 10
    jae  pm_two
    Say  msgZero                ; residuo 5 -> "05"
pm_two:
    call PrintU32
    Say  msgMXN
    pop  edx
    pop  ebx
    pop  eax
    ret
PrintMXN ENDP


; ValidateCode : valida ABC-123 (3 mayusculas, guion, 3 digitos, fin de cadena)
; Entrada : ESI = cadena.
; Salida  : CF=1 si es invalida.
; (ESI se conserva)

ValidateCode PROC
    push eax
    push ecx
    push esi
    mov  ecx, 3
vc_l1:
    mov  al, [esi]
    cmp  al, 'A'
    jb   vc_bad
    cmp  al, 'Z'
    ja   vc_bad
    inc  esi
    loop vc_l1
    mov  al, [esi]
    cmp  al, '-'
    jne  vc_bad
    inc  esi
    mov  ecx, 3
vc_l2:
    mov  al, [esi]
    cmp  al, '0'
    jb   vc_bad
    cmp  al, '9'
    ja   vc_bad
    inc  esi
    loop vc_l2
    cmp  BYTE PTR [esi], 0
    jne  vc_bad
    clc
    jmp  vc_done
vc_bad:
    stc
vc_done:
    pop  esi
    pop  ecx
    pop  eax
    ret
ValidateCode ENDP


; ValidateName : 1 a 25 caracteres ASCII imprimibles y terminador 0.
; Entrada : ESI = cadena.
; Salida  : CF=1 si es invalida.
;  EFLAGS (ESI se conserva)

ValidateName PROC
    push eax
    push ecx
    push esi
    xor  ecx, ecx
vn_loop:
    mov  al, [esi]
    test al, al
    jz   vn_end
    cmp  al, 32
    jb   vn_bad
    cmp  al, 126
    ja   vn_bad
    cmp  al, ';'                ; separador del archivo
    je   vn_bad
    inc  esi
    inc  ecx
    cmp  ecx, 25
    jbe  vn_loop
    jmp  vn_bad                 ; mas de 25 caracteres
vn_end:
    test ecx, ecx
    jz   vn_bad                 ; vacio
    clc
    jmp  vn_done
vn_bad:
    stc
vn_done:
    pop  esi
    pop  ecx
    pop  eax
    ret
ValidateName ENDP

; CodesEqual : compara los 7 caracteres de dos codigos.
; Entrada : ESI, EDI = codigos.
; Salida  : ZF=1 si son iguales.


CodesEqual PROC
    push eax
    push ecx
    push esi
    push edi
    mov  ecx, 7
ce_loop:
    mov  al, [esi]
    cmp  al, [edi]
    jne  ce_done                ; ZF=0
    inc  esi
    inc  edi
    loop ce_loop
    xor  eax, eax               ; llegaron los 7 iguales: fuerza ZF=1
ce_done:
    pop  edi                    ; POP no altera las banderas
    pop  esi
    pop  ecx
    pop  eax
    ret
CodesEqual ENDP


; FindProduct : busca un codigo en el catalogo (recorrido con ESI).
; Entrada : EDI = codigo (cadena).
; Salida  : CF=0 y ESI = registro encontrado; CF=1 si no existe.
; Modifica: ESI, EFLAGS


FindProduct PROC
    push ecx
    mov  esi, OFFSET products
    mov  ecx, prodCount
    test ecx, ecx
    jz   fp_nf
fp_loop:
    call CodesEqual
    je   fp_found
    add  esi, REC_SIZE
    dec  ecx
    jnz  fp_loop
fp_nf:
    stc
    pop  ecx
    ret
fp_found:
    clc
    pop  ecx
    ret
FindProduct ENDP

; ShowRecord : imprime un producto.
; Entrada : ESI = registro.
; Modifica: EFLAGS

ShowRecord PROC
    push eax
    push edx
    mov  edx, esi               ; codigo (offset 0)
    call WriteString
    Say  msgSep
    lea  edx, [esi+OFF_NAME]
    call WriteString
    Say  msgSep
    mov  eax, [esi+OFF_PRICE]
    call PrintMXN
    Say  msgExist
    mov  eax, [esi+OFF_STOCK]
    call PrintU32
    call Crlf
    pop  edx
    pop  eax
    ret
ShowRecord ENDP

; AskProduct : pide un codigo, lo valida y lo localiza.
; Salida  : CF=0 y ESI = registro; CF=1 si hubo error (mensaje ya mostrado).
; Modifica: ESI, EDI, EAX, EFLAGS

AskProduct PROC
    Say  msgAskCode
    call GetInput
    jc   ap_err
    mov  esi, OFFSET inbuf
    call ValidateCode
    jc   ap_badfmt
    mov  edi, OFFSET inbuf
    call FindProduct
    jc   ap_nf
    clc
    ret
ap_badfmt:
    Say  msgBadCode
    stc
    ret
ap_nf:
    Say  msgNotFound
ap_err:
    stc
    ret
AskProduct ENDP


; AskQuantity : pide una cantidad entera 1..100.
; Salida  : EAX = cantidad; CF=1 si es invalida (mensaje ya mostrado).
; Modifica: EAX, EFLAGS (ESI se conserva)

AskQuantity PROC
    push esi
    Say  msgAskQty
    call GetInput
    jc   aq_err
    mov  esi, OFFSET inbuf
    call ParseUInt
    jc   aq_inv
    test eax, eax
    jz   aq_inv
    cmp  eax, MAX_STOCK
    ja   aq_inv
    clc
    jmp  aq_done
aq_inv:
    Say  msgBadQty
aq_err:
    stc
aq_done:
    pop  esi
    ret
AskQuantity ENDP

; ConfirmYN : lee una respuesta S/N.
; Salida  : CF=0 si respondio S/s; CF=1 en cualquier otro caso.
; Modifica: EAX, EFLAGS

ConfirmYN PROC
    call ReadLine
    jc   cy_no
    cmp  eax, 1
    jne  cy_no
    mov  al, [inbuf]
    or   al, 20h                ; a minuscula
    cmp  al, 's'
    jne  cy_no
    clc
    ret
cy_no:
    stc
    ret
ConfirmYN ENDP

; DoRegister : alta de producto. Todo se valida y se guarda en variables
;              temporales; el catalogo solo cambia al final (sin cambios
;              parciales).
; Modifica: EAX, EBX, ECX, EDX, ESI, EDI, EFLAGS


DoRegister PROC
    cmp  prodCount, PROD_MAX
    jb   dr_space
    Say  msgFull
    ret
dr_space:
    Say  msgAskCode
    call GetInput
    jc   dr_end
    mov  esi, OFFSET inbuf
    call ValidateCode
    jc   dr_badcode
    mov  edi, OFFSET inbuf
    call FindProduct
    jnc  dr_dup
    mov  esi, OFFSET inbuf
    mov  edi, OFFSET tmpCode
    mov  ecx, CODE_SIZE
    call CopyPad
    Say  msgAskName
    call GetInput
    jc   dr_end
    mov  esi, OFFSET inbuf
    call ValidateName
    jc   dr_badname
    mov  edi, OFFSET tmpName
    mov  ecx, NAME_SIZE
    call CopyPad
    Say  msgAskPrice
    call GetInput
    jc   dr_end
    mov  esi, OFFSET inbuf
    call ParsePrice
    jc   dr_badprice
    mov  tmpPrice, eax
    Say  msgAskStock
    call GetInput
    jc   dr_end
    mov  esi, OFFSET inbuf
    call ParseUInt
    jc   dr_badstock
    cmp  eax, MAX_STOCK
    ja   dr_badstock
    mov  tmpStock, eax
    ;  confirmacion: se escribe el registro en la tabla 
    mov  eax, prodCount
    imul eax, eax, REC_SIZE
    mov  ebx, OFFSET products
    add  ebx, eax               ; EBX = registro destino
    mov  esi, OFFSET tmpCode
    mov  edi, ebx
    mov  ecx, CODE_SIZE
    call CopyPad
    mov  esi, OFFSET tmpName
    lea  edi, [ebx+OFF_NAME]
    mov  ecx, NAME_SIZE
    call CopyPad
    mov  eax, tmpPrice
    mov  [ebx+OFF_PRICE], eax
    mov  eax, tmpStock
    mov  [ebx+OFF_STOCK], eax
    inc  prodCount
    mov  dirty, 1
    Say  msgRegOk
    ret
dr_badcode:
    Say  msgBadCode
    ret
dr_dup:
    Say  msgDup
    ret
dr_badname:
    Say  msgBadName
    ret
dr_badprice:
    Say  msgBadPrice
    ret
dr_badstock:
    Say  msgBadStock
dr_end:
    ret
DoRegister ENDP

; DoShowAll : muestra el inventario recorriendo la tabla con ESI.
; Modifica: ECX, ESI, EFLAGS

DoShowAll PROC
    mov  ecx, prodCount
    test ecx, ecx
    jnz  sa_go
    Say  msgEmpty
    ret
sa_go:
    mov  esi, OFFSET products
sa_loop:
    call ShowRecord
    add  esi, REC_SIZE
    loop sa_loop
    ret
DoShowAll ENDP

; DoSearch : busca por codigo y muestra el producto.
; Modifica: EAX, ESI, EDI, EFLAGS

DoSearch PROC
    call AskProduct
    jc   ds_end
    call ShowRecord
ds_end:
    ret
DoSearch ENDP


; DoReceive : suma unidades a un producto existente (maximo 100).
; Modifica: EAX, ECX, ESI, EDI, EFLAGS

DoReceive PROC
    call AskProduct
    jc   rv_end
    call AskQuantity            ; EAX = cantidad (ESI se conserva)
    jc   rv_end
    mov  ecx, [esi+OFF_STOCK]
    add  ecx, eax
    jc   rv_ovf
    cmp  ecx, MAX_STOCK
    ja   rv_excess
    mov  [esi+OFF_STOCK], ecx   ; se actualiza solo si todo es valido
    mov  dirty, 1
    Say  msgRecvOk
    mov  eax, ecx
    call PrintU32
    call Crlf
    ret
rv_ovf:
    Say  msgOvf
    ret
rv_excess:
    Say  msgExcess
rv_end:
    ret
DoReceive ENDP

; DoSell : venta de un solo producto con descuento por cantidad.
;   base      = precio * cantidad          (MUL, CF=1 si desborda)
;   descuento = base*10/100 si cantidad>=10 (division entera: se descartan
;               las fracciones de centavo); 0 en otro caso
;   final     = base - descuento
; Existencias e ingresos se modifican SOLO despues de pasar todas las pruebas.

DoSell PROC
    call AskProduct
    jc   sl_end
    call ShowRecord
    call AskQuantity
    jc   sl_end
    mov  ebx, eax               ; EBX = cantidad
    cmp  ebx, [esi+OFF_STOCK]
    ja   sl_nostock
    mov  eax, [esi+OFF_PRICE]
    mul  ebx                    ; EDX:EAX = precio*cantidad
    jc   sl_ovf
    mov  ecx, eax               ; ECX = importe base
    xor  edi, edi               ; EDI = descuento
    cmp  ebx, DISC_MIN_QTY
    jb   sl_calc
    mov  eax, ecx
    mov  edi, DISC_PCT
    mul  edi                    ; base*10
    jc   sl_ovf
    mov  edi, 100
    div  edi                    ; EAX = base*10/100 (EDX=0 tras MUL sin acarreo)
    mov  edi, eax               ; descuento (sin fraccion de centavo)
sl_calc:
    mov  edx, ecx
    sub  edx, edi               ; EDX = importe final
    mov  eax, revenue
    add  eax, edx               ; nuevos ingresos
    jc   sl_ovf
   ; ---- todo valido: se confirma la venta ----
    mov  revenue, eax
    mov  eax, [esi+OFF_STOCK]
    sub  eax, ebx
    mov  [esi+OFF_STOCK], eax
    mov  dirty, 1
    Say  msgBase
    mov  eax, ecx
    call PrintMXN
    call Crlf
    test edi, edi
    jz   sl_nodisc
    Say  msgDisc
    mov  eax, edi
    call PrintMXN
    call Crlf
    jmp  sl_final
sl_nodisc:
    Say  msgNoDisc
sl_final:
    Say  msgFinal
    mov  eax, edx
    call PrintMXN
    call Crlf
    Say  msgSaleOk
    ret
sl_nostock:
    Say  msgNoStock
    ret
sl_ovf:
    Say  msgOvf
sl_end:
    ret
DoSell ENDP

; DoSummary : unidades, valor del inventario e ingresos de la sesion.
; Modifica: EAX, EBX, ECX, EDX, ESI, EDI, EFLAGS

DoSummary PROC
    xor  ebx, ebx               ; unidades
    xor  edi, edi               ; valor (centavos)
    mov  esi, OFFSET products
    mov  ecx, prodCount
    test ecx, ecx
    jz   sm_print
sm_loop:
    add  ebx, [esi+OFF_STOCK]
    mov  eax, [esi+OFF_PRICE]
    mul  DWORD PTR [esi+OFF_STOCK]
    jc   sm_ovf
    add  edi, eax
    jc   sm_ovf
    add  esi, REC_SIZE
    loop sm_loop
sm_print:
    Say  msgSumUnits
    mov  eax, ebx
    call PrintU32
    call Crlf
    Say  msgSumValue
    mov  eax, edi
    call PrintMXN
    call Crlf
    Say  msgSumRev
    mov  eax, revenue
    call PrintMXN
    call Crlf
    ret
sm_ovf:
    Say  msgOvf
    ret
DoSummary ENDP

; AppendStr : agrega una cadena (sin el 00h) al buffer de salida.
; Entrada : EDX = cadena origen, EDI = destino.
; Salida  : EDI avanza al final del texto copiado.
; Modifica: EDI, EFLAGS

AppendStr PROC
    push eax
    push edx
as_loop:
    mov  al, [edx]
    test al, al
    jz   as_done
    mov  [edi], al
    inc  edx
    inc  edi
    jmp  as_loop
as_done:
    pop  edx
    pop  eax
    ret
AppendStr ENDP

; ToDecStr : entero sin signo -> cadena decimal en numbuf (cociente/residuo).
; Entrada : EAX = valor.
; Salida  : EDX = inicio de la cadena (terminada en 00h).
; Modifica: EDX, EFLAGS

ToDecStr PROC
    push eax
    push ebx
    push ecx
    mov  ecx, OFFSET numbuf + 11
    mov  BYTE PTR [ecx], 0
    mov  ebx, 10
td_loop:
    xor  edx, edx
    div  ebx                    ; EAX = cociente, EDX = residuo
    add  dl, '0'
    dec  ecx
    mov  [ecx], dl
    test eax, eax
    jnz  td_loop
    mov  edx, ecx
    pop  ecx
    pop  ebx
    pop  eax
    ret
ToDecStr ENDP

; AppendU32 : agrega EAX en decimal al buffer de salida.
; Entrada : EAX = valor, EDI = destino.   Salida: EDI avanza.
; Modifica: EDI, EFLAGS

AppendU32 PROC
    push edx
    call ToDecStr
    call AppendStr
    pop  edx
    ret
AppendU32 ENDP

; AppendMXN : agrega centavos como pesos con 2 decimales ("45.50", "5.05").
; Entrada : EAX = centavos, EDI = destino.   Salida: EDI avanza.
; Modifica: EDI, EFLAGS

AppendMXN PROC
    push eax
    push ebx
    push edx
    mov  ebx, 100
    xor  edx, edx
    div  ebx                    ; EAX = pesos, EDX = centavos
    push edx
    call AppendU32
    mov  edx, OFFSET msgDot
    call AppendStr
    pop  eax                    ; centavos
    cmp  eax, 10
    jae  am_two
    mov  edx, OFFSET msgZero    ; residuo < 10 -> "0" + digito
    call AppendStr
am_two:
    call AppendU32
    pop  edx
    pop  ebx
    pop  eax
    ret
AppendMXN ENDP

; SaveCatalog : arma el texto en outbuf (recorriendo la tabla con ESI) y lo
;               escribe en inventario.dat.
; Salida  : CF=1 si fallo (CreateOutputFile, WriteToFile o CloseFile).
; Modifica: EAX, ECX, EDX, ESI, EDI, EFLAGS

SaveCatalog PROC
    mov  edi, OFFSET outbuf
    mov  edx, OFFSET txtHeader
    call AppendStr
    mov  esi, OFFSET products
    mov  ecx, prodCount
    test ecx, ecx
    jz   sv_write
sv_loop:
    mov  edx, esi               ; codigo
    call AppendStr
    mov  edx, OFFSET txtSemi
    call AppendStr
    lea  edx, [esi+OFF_NAME]    ; nombre
    call AppendStr
    mov  edx, OFFSET txtSemi
    call AppendStr
    mov  eax, [esi+OFF_PRICE]   ; precio 45.50
    call AppendMXN
    mov  edx, OFFSET txtSemi
    call AppendStr
    mov  eax, [esi+OFF_STOCK]   ; existencia
    call AppendU32
    mov  edx, OFFSET txtCRLF
    call AppendStr
    add  esi, REC_SIZE
    dec  ecx
    jnz  sv_loop
sv_write:
    mov  eax, edi
    sub  eax, OFFSET outbuf     ; bytes a escribir
    mov  expected, eax
    mov  edx, OFFSET fileName
    call CreateOutputFile       ; EAX = handle o INVALID_HANDLE_VALUE
    cmp  eax, INVALID_HANDLE_VALUE
    je   sv_err
    mov  hFile, eax
    mov  edx, OFFSET outbuf
    mov  ecx, expected
    call WriteToFile            ; EAX = bytes escritos
    push eax
    mov  eax, hFile
    call CloseFile              ; EAX<>0 si cierra bien
    mov  ecx, eax
    pop  eax
    cmp  eax, expected          ; se escribieron todos los bytes?
    jne  sv_err
    test ecx, ecx
    jz   sv_err
    mov  dirty, 0
    Say  msgSaved
    clc
    ret
sv_err:
    Say  msgSaveErr
    stc
    ret
SaveCatalog ENDP

; ReadField : copia a fieldbuf los caracteres del texto hasta ';', CR, LF o 00h.
; Entrada : EBX = posicion en el texto, ECX = maximo de caracteres.
; Salida  : EBX apunta al terminador, AL = terminador, fieldbuf = campo + 00h.
;           CF=1 si el campo excede ECX caracteres.

ReadField PROC
    push ecx
    push edi
    mov  edi, OFFSET fieldbuf
rf_loop:
    mov  al, [ebx]
    cmp  al, ';'
    je   rf_end
    test al, al
    jz   rf_end
    cmp  al, 13
    je   rf_end
    cmp  al, 10
    je   rf_end
    test ecx, ecx
    jz   rf_bad
    mov  [edi], al
    inc  edi
    inc  ebx
    dec  ecx
    jmp  rf_loop
rf_end:
    mov  BYTE PTR [edi], 0
    clc
    jmp  rf_done
rf_bad:
    stc
rf_done:
    pop  edi
    pop  ecx
    ret
ReadField ENDP

; LoadCatalog : lee inventario.dat a loadbuf, interpreta el texto y lo valida
;               en tmpTable. Solo si TODO es valido reemplaza el catalogo.
; Validaciones: archivo existe, lectura sin error, tamano < capacidad, linea
;   "INV1", maximo 10 lineas, cada campo (codigo, nombre, precio, existencia)
;   valido, y sin codigos duplicados.
; Salida  : CF=1 si fallo.
; Modifica: EAX, EBX, ECX, EDX, ESI, EDI, EFLAGS

LoadCatalog PROC
    mov  edx, OFFSET fileName
    call OpenInputFile
    cmp  eax, INVALID_HANDLE_VALUE
    je   ld_nofile
    mov  hFile, eax
    cld
    mov  edi, OFFSET loadbuf    ; limpia el buffer (queda el 00h final)
    mov  ecx, FILE_CAP + 1
    xor  al, al
    rep  stosb
    mov  edi, OFFSET tmpTable   ; limpia la tabla temporal
    mov  ecx, PROD_MAX*REC_SIZE
    rep  stosb
    mov  tmpCount, 0
    mov  eax, hFile
    mov  edx, OFFSET loadbuf
    mov  ecx, FILE_CAP          ; capacidad (distinta de bytes leidos)
    call ReadFromFile           ; CF=1 si error; EAX = bytes leidos
    pushfd
    mov  bytesRead, eax
    mov  eax, hFile
    call CloseFile
    popfd
    jc   ld_readerr
    cmp  bytesRead, 6
    jb   ld_invalid
    cmp  bytesRead, FILE_CAP    ; si llena el buffer, el archivo es demasiado grande
    jae  ld_invalid
    mov  ebx, OFFSET loadbuf    ; EBX = posicion en el texto
    cmp  BYTE PTR [ebx], 'I'
    jne  ld_invalid
    cmp  BYTE PTR [ebx+1], 'N'
    jne  ld_invalid
    cmp  BYTE PTR [ebx+2], 'V'
    jne  ld_invalid
    cmp  BYTE PTR [ebx+3], '1'
    jne  ld_invalid
    add  ebx, 4
    cmp  BYTE PTR [ebx], 13
    jne  ld_hlf
    inc  ebx
ld_hlf:
    cmp  BYTE PTR [ebx], 10
    jne  ld_invalid
    inc  ebx
ld_line:
    mov  al, [ebx]              ; salta saltos de linea sobrantes
    cmp  al, 13
    je   ld_skip
    cmp  al, 10
    jne  ld_chk
ld_skip:
    inc  ebx
    jmp  ld_line
ld_chk:
    test al, al                 ; fin del texto
    jz   ld_dups
    cmp  tmpCount, PROD_MAX
    jae  ld_invalid             ; mas de 10 productos
    mov  eax, tmpCount
    imul eax, eax, REC_SIZE
    add  eax, OFFSET tmpTable
    mov  curRec, eax            ; registro temporal destino
    mov  ecx, 7
    call ReadField
    jc   ld_invalid
    cmp  al, ';'
    jne  ld_invalid
    mov  esi, OFFSET fieldbuf
    call ValidateCode
    jc   ld_invalid
    mov  edi, curRec
    mov  ecx, CODE_SIZE
    call CopyPad
    inc  ebx                    ; salta ';'
    mov  ecx, 25
    call ReadField
    jc   ld_invalid
    cmp  al, ';'
    jne  ld_invalid
    mov  esi, OFFSET fieldbuf
    call ValidateName
    jc   ld_invalid
    mov  edi, curRec
    add  edi, OFF_NAME
    mov  ecx, NAME_SIZE
    call CopyPad
    inc  ebx
    mov  ecx, 7
    call ReadField
    jc   ld_invalid
    cmp  al, ';'
    jne  ld_invalid
    mov  esi, OFFSET fieldbuf
    call ParsePrice             ; EAX = centavos
    jc   ld_invalid
    mov  edi, curRec
    mov  [edi+OFF_PRICE], eax
    inc  ebx
    mov  ecx, 3
    call ReadField
    jc   ld_invalid
    cmp  al, ';'
    je   ld_invalid             ; sobran campos
    mov  esi, OFFSET fieldbuf
    call ParseUInt
    jc   ld_invalid
    cmp  eax, MAX_STOCK
    ja   ld_invalid
    mov  edi, curRec
    mov  [edi+OFF_STOCK], eax
    inc  tmpCount
    jmp  ld_line
ld_dups:
    mov  esi, OFFSET tmpTable
    mov  ecx, tmpCount
ld_out:
    cmp  ecx, 1
    jbe  ld_accept
    mov  edi, esi
    add  edi, REC_SIZE
    mov  edx, ecx
    dec  edx
ld_in:
    call CodesEqual
    je   ld_invalid
    add  edi, REC_SIZE
    dec  edx
    jnz  ld_in
    add  esi, REC_SIZE
    dec  ecx
    jmp  ld_out
ld_accept:
    cld
    mov  eax, tmpCount
    mov  prodCount, eax
    mov  esi, OFFSET tmpTable
    mov  edi, OFFSET products
    mov  ecx, PROD_MAX*REC_SIZE
    rep  movsb
    mov  dirty, 0
    Say  msgLoaded
    clc
    ret
ld_nofile:
    Say  msgNoFile
    stc
    ret
ld_readerr:
    Say  msgReadErr
    stc
    ret
ld_invalid:
    Say  msgInvalid
    stc
    ret
LoadCatalog ENDP


main PROC
    mov  mainEsp, esp
    Say  msgBanner
    call LoadCatalog            ; intenta recuperar el catalogo al iniciar
menu_loop:
    cmp  esp, mainEsp
    jne  stack_err
    Say  msgMenu
    call ReadLine
    jc   bad_opt
    cmp  eax, 1
    jne  bad_opt
    mov  al, [inbuf]
    cmp  al, '1'
    jne  m2
    call DoRegister
    jmp  menu_loop
m2: cmp  al, '2'
    jne  m3
    call DoShowAll
    jmp  menu_loop
m3: cmp  al, '3'
    jne  m4
    call DoSearch
    jmp  menu_loop
m4: cmp  al, '4'
    jne  m5
    call DoReceive
    jmp  menu_loop
m5: cmp  al, '5'
    jne  m6
    call DoSell
    jmp  menu_loop
m6: cmp  al, '6'
    jne  m7
    call DoSummary
    jmp  menu_loop
m7: cmp  al, '7'
    jne  m8
    call SaveCatalog
    jmp  menu_loop
m8: cmp  al, '8'
    jne  m9
    cmp  dirty, 0
    je   m8_go
    Say  msgUnsaved
    call ConfirmYN
    jc   menu_loop
m8_go:
    call LoadCatalog
    jmp  menu_loop
m9: cmp  al, '9'
    jne  bad_opt
    cmp  dirty, 0
    je   quit
    Say  msgUnsaved
    call ConfirmYN
    jc   menu_loop
quit:
    exit
bad_opt:
    Say  msgBadOpt
    jmp  menu_loop
stack_err:
    Say  msgStackErr
    exit
main ENDP
END main