; ============================================================================
; Proyecto Unidad 3 - Ventas e inventario en ensamblador (MASM x86, Irvine32)
; Negocio : Papeleria
; Regla   : DESCUENTO POR CANTIDAD -> si se venden 10 o mas unidades de un
;           producto, se descuenta el 10% del importe base. La fraccion de
;           centavo se descarta (division entera).
; Archivo : inventario.dat (binario). Ver README.md para el formato.
; Convenciones: todos los procedimientos preservan los registros que NO
;           aparecen en "Modifica". Los resultados con error usan CF=1.
;
; UNIDAD 3: mismas funciones, menu y validaciones que la Unidad 2. Cambios:
;   - Macros: Fail, Reject, Ask, AskCheck, JNotRange, JNotDigit, Put, ShowU32,
;             ShowMXN, CopyField, RecAddr, FileBytes, ParseBetween, MenuItem (LOCAL).
;   - PROC ... USES en lugar de push/pop manuales.
;   - Procedimientos nuevos: ParseRange, CalcDiscount, CalcSale, ConfirmDiscard,
;             DoLoad, ToDecStr, SplitMXN, ZeroMem, ReadInventoryFile,
;             ValidateTable, HasDuplicates.
;   - Constante MAGIC_INV1 para comparar la firma "INV1" de una sola vez.
; ============================================================================
INCLUDE Irvine32.inc

; ---------------------------- Constantes ------------------------------------
PROD_MAX     EQU 10
REC_SIZE     EQU 44            ; tamano de cada registro de producto
OFF_CODE     EQU 0             ; 8 bytes  : "ABC-123",0
OFF_NAME     EQU 8             ; 26 bytes : nombre (1..25) + 0
OFF_PRICE    EQU 36            ; DWORD    : centavos (1..999999)
OFF_STOCK    EQU 40            ; DWORD    : existencia (0..100)
CODE_SIZE    EQU 8
NAME_SIZE    EQU 26
HDR_SIZE     EQU 8             ; firma INV1 (4) + conteo (4)
FILE_MAX     EQU HDR_SIZE + PROD_MAX*REC_SIZE   ; 448 bytes: tamano maximo valido
FILE_CAP     EQU FILE_MAX + 1            ; se lee 1 byte de mas para detectar exceso
INBUF_MAX    EQU 63
MAX_PRICE    EQU 999999
MAX_STOCK    EQU 100
DISC_MIN_QTY EQU 10
DISC_PCT     EQU 10
MAGIC_INV1   EQU 31564E49h     ; "INV1" leido como DWORD (little-endian)

; ============================================================================
; Macros
; ============================================================================

; Say : muestra una cadena constante (preserva EDX)
Say MACRO txt
    push edx
    mov  edx, OFFSET txt
    call WriteString
    pop  edx
ENDM

; Fail : muestra un error y sale del procedimiento con CF=1.
Fail MACRO txt
    Say  txt
    stc
    ret
ENDM

; Reject : muestra un mensaje de rechazo y sale del procedimiento (sin tocar CF).
Reject MACRO txt
    Say  txt
    ret
ENDM

; Ask : muestra el prompt, captura con GetInput y deja ESI = OFFSET inbuf.
;       CF (error de GetInput) se conserva porque MOV no modifica banderas.
Ask MACRO prompt
    Say  prompt
    call GetInput
    mov  esi, OFFSET inbuf
ENDM

; JNotRange : salta a lbl si rg esta fuera de [vmin..vmax] (sin signo).
JNotRange MACRO rg, vmin, vmax, lbl
    cmp  rg, vmin
    jb   lbl
    cmp  rg, vmax
    ja   lbl
ENDM

; JNotDigit : salta a lbl si rg no es un caracter '0'..'9'.
JNotDigit MACRO rg, lbl
    JNotRange rg, '0', '9', lbl
ENDM

; Put : imprime un registro/variable como decimal sin signo. Modifica: EAX
Put MACRO src
    mov  eax, src
    call PrintU32
ENDM

; ShowU32 / ShowMXN : "etiqueta" + valor + salto de linea. Modifican: EAX, EFLAGS
ShowU32 MACRO txt, src
    Say  txt
    Put  src
    call Crlf
ENDM

ShowMXN MACRO txt, src
    Say  txt
    mov  eax, src
    call PrintMXN
    call Crlf
ENDM

; CopyField : copia la cadena src al campo dst (cualquier operando de memoria)
;             rellenando con 0. Modifica: ESI, EDI, ECX, EFLAGS
CopyField MACRO src, dst, sz
    mov  esi, OFFSET src
    lea  edi, dst
    mov  ecx, sz
    call CopyPad
ENDM

; RecAddr : dst = OFFSET tbl + idx * REC_SIZE. dst = registro de 32 bits.
RecAddr MACRO dst, tbl, idx
    mov  dst, idx
    imul dst, dst, REC_SIZE
    add  dst, OFFSET tbl
ENDM

; ParseBetween : ESI = cadena; EAX = valor en [vmin..vmax]; CF=1 si invalido.
;                Prepara EDX/ECX para ParseRange. Modifica: EAX, ECX, EDX, EFLAGS
ParseBetween MACRO vmin, vmax
    mov  edx, vmin
    mov  ecx, vmax
    call ParseRange
ENDM

; FileBytes : dst = HDR_SIZE + cnt * REC_SIZE (bytes que ocupa el archivo con
;             cnt registros). Se usa al guardar y al validar el tamano al cargar.
;             dst = registro de 32 bits, cnt = registro o variable. Modifica: dst, EFLAGS
FileBytes MACRO dst, cnt
    imul dst, cnt, REC_SIZE
    add  dst, HDR_SIZE
ENDM

; AskCheck : pregunta, captura y valida con el procedimiento check.
;            Salta a quit si la captura fallo (mensaje ya mostrado por GetInput)
;            y a bad si check devuelve CF=1. ESI = OFFSET inbuf al entrar a check.
AskCheck MACRO prompt, check, bad, quit
    Ask  prompt
    jc   quit
    call check
    jc   bad
ENDM

; MenuItem : si AL = key llama a target y regresa al menu. LOCAL evita
;            etiquetas duplicadas al usarla varias veces.
MenuItem MACRO key, target
    LOCAL skip
    cmp  al, key
    jne  skip
    call target
    jmp  menu_loop
skip:
ENDM

.data
; --- Bloque contiguo que se escribe tal cual en el archivo -------------------
fileHdr     BYTE  "INV1"                      ; 4 bytes de firma
prodCount   DWORD 0                           ; numero de productos
products    BYTE  PROD_MAX*REC_SIZE DUP(0)    ; tabla de registros
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
loadbuf     BYTE  FILE_CAP+1 DUP(0)

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

; ============================================================================
; CopyPad : copia una cadena a un campo de tamano fijo y rellena con 0.
; Entrada : ESI = origen (cadena terminada en 0), EDI = destino, ECX = tamano
;           del campo (incluye el 0 final).
; Salida  : campo con a lo mas ECX-1 caracteres + ceros.
; Modifica: EFLAGS
; ============================================================================
CopyPad PROC USES eax ecx esi edi
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
    ret
CopyPad ENDP

; ============================================================================
; ZeroMem : pone en cero un bloque de memoria.
; Entrada : EDI = inicio, ECX = numero de bytes.
; Modifica: EFLAGS
; ============================================================================
ZeroMem PROC USES eax ecx edi
    cld
    xor  al, al
    rep  stosb
    ret
ZeroMem ENDP

; ============================================================================
; ReadLine : captura una linea en inbuf con ReadString.
; Salida  : EAX = caracteres leidos; CF=1 si la linea era demasiado larga
;           (el resto se descarta leyendo hasta vaciar la linea).
; Modifica: EAX, EFLAGS
; ============================================================================
ReadLine PROC USES edx ecx
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
    ret
ReadLine ENDP

; ============================================================================
; GetInput : ReadLine + rechazo de entrada vacia o demasiado larga.
; Salida  : EAX = longitud; CF=1 si hay error (ya muestra el mensaje).
; Modifica: EAX, EFLAGS
; ============================================================================
GetInput PROC
    call ReadLine
    jc   gi_bad
    test eax, eax
    jnz  gi_ok
gi_bad:
    Fail msgBadInput
gi_ok:
    clc
    ret
GetInput ENDP

; ============================================================================
; ParseUInt : cadena de digitos -> entero sin signo (solo '0'..'9').
; Entrada : ESI = cadena terminada en 0.
; Salida  : EAX = valor; CF=1 si vacia, con caracteres no permitidos o si
;           desborda 32 bits.
; Modifica: EAX, EFLAGS (ESI se conserva)
; ============================================================================
ParseUInt PROC USES ebx ecx edx esi
    xor  eax, eax
    xor  ecx, ecx               ; contador de digitos
pu_loop:
    movzx ebx, BYTE PTR [esi]
    test bl, bl
    jz   pu_end
    JNotDigit bl, pu_bad
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
    ret
ParseUInt ENDP

; ============================================================================
; ParseRange : ParseUInt + comprobacion de rango [EDX..ECX].
; Entrada : ESI = cadena, EDX = minimo, ECX = maximo.
; Salida  : EAX = valor; CF=1 si es invalido o esta fuera de rango.
; Modifica: EAX, EFLAGS
; ============================================================================
ParseRange PROC
    call ParseUInt
    jc   pr_end
    cmp  eax, edx
    jb   pr_bad
    cmp  eax, ecx
    ja   pr_bad
    clc
    ret
pr_bad:
    stc
pr_end:
    ret
ParseRange ENDP

; ============================================================================
; ParsePrice : "185.50" -> 18550 centavos. Acepta enteros o punto con 1 o 2
;              decimales. Rechaza simbolos, separadores de miles, ".5", "5.",
;              tercer decimal y fuera de rango (1..999999 centavos).
; Entrada : ESI = cadena terminada en 0.
; Salida  : EAX = centavos; CF=1 si es invalida.
; Modifica: EAX, EFLAGS (ESI se conserva)
; ============================================================================
ParsePrice PROC USES ebx ecx edx esi
    xor  eax, eax               ; pesos
    xor  ecx, ecx               ; digitos enteros
pp_int:
    movzx edx, BYTE PTR [esi]
    test dl, dl
    jz   pp_intEnd
    cmp  dl, '.'
    je   pp_intEnd
    JNotDigit dl, pp_bad
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
    JNotDigit dl, pp_bad
    sub  edx, '0'
    imul edx, edx, 10           ; decenas de centavo
    add  ebx, edx
    inc  esi
    cmp  BYTE PTR [esi], 0
    je   pp_range               ; un solo decimal: 185.5 -> 18550
    movzx edx, BYTE PTR [esi]   ; segundo decimal
    JNotDigit dl, pp_bad
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
    ret
ParsePrice ENDP

; ============================================================================
; ToDecStr : convierte EAX a cadena decimal sin signo en numbuf (division
;            entre 10). Los digitos salen en orden inverso (residuos), por
;            eso se escriben desde el final del buffer hacia atras.
; Entrada : EAX = valor.
; Salida  : EDX = inicio de la cadena (terminada en 00h).
; Modifica: EDX, EFLAGS
; ============================================================================
ToDecStr PROC USES eax ebx edi
    mov  edi, OFFSET numbuf + 11
    mov  BYTE PTR [edi], 0      ; terminador 00h
    mov  ebx, 10
ts_loop:
    xor  edx, edx               ; dividendo = EDX:EAX
    div  ebx                    ; EAX = cociente, EDX = residuo (0..9)
    add  dl, '0'                ; digito -> ASCII
    dec  edi
    mov  [edi], dl
    test eax, eax
    jnz  ts_loop
    mov  edx, edi
    ret
ToDecStr ENDP

; ============================================================================
; PrintU32 : muestra EAX como decimal sin signo.
; Entrada : EAX = valor.
; Modifica: EFLAGS
; ============================================================================
PrintU32 PROC USES edx
    call ToDecStr
    call WriteString
    ret
PrintU32 ENDP

; ============================================================================
; SplitMXN : separa centavos en pesos y centavos (DIV entre 100).
; Entrada : EAX = centavos.
; Salida  : EAX = pesos, EDX = centavos (0..99).
; Modifica: EAX, EDX, EFLAGS
; ============================================================================
SplitMXN PROC USES ebx
    mov  ebx, 100
    xor  edx, edx
    div  ebx
    ret
SplitMXN ENDP

; ============================================================================
; PrintMXN : muestra centavos como "$1234.05 MXN".
; Entrada : EAX = centavos.
; Modifica: EFLAGS
; ============================================================================
PrintMXN PROC USES eax edx
    Say  msgDollar
    call SplitMXN               ; EAX = pesos, EDX = centavos
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
    ret
PrintMXN ENDP

; ============================================================================
; ValidateCode : valida ABC-123 (3 mayusculas, guion, 3 digitos, fin de cadena)
; Entrada : ESI = cadena.
; Salida  : CF=1 si es invalida.
; Modifica: EFLAGS (ESI se conserva)
; ============================================================================
ValidateCode PROC USES eax ecx esi
    mov  ecx, 3
vc_l1:
    mov  al, [esi]
    JNotRange al, 'A', 'Z', vc_bad
    inc  esi
    loop vc_l1
    mov  al, [esi]
    cmp  al, '-'
    jne  vc_bad
    inc  esi
    mov  ecx, 3
vc_l2:
    mov  al, [esi]
    JNotDigit al, vc_bad
    inc  esi
    loop vc_l2
    cmp  BYTE PTR [esi], 0
    jne  vc_bad
    clc
    jmp  vc_done
vc_bad:
    stc
vc_done:
    ret
ValidateCode ENDP

; ============================================================================
; ValidateName : 1 a 25 caracteres ASCII imprimibles y terminador 0.
; Entrada : ESI = cadena.
; Salida  : CF=1 si es invalida.
; Modifica: EFLAGS (ESI se conserva)
; ============================================================================
ValidateName PROC USES eax ecx esi
    xor  ecx, ecx
vn_loop:
    mov  al, [esi]
    test al, al
    jz   vn_end
    JNotRange al, 32, 126, vn_bad
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
    ret
ValidateName ENDP

; ============================================================================
; ValidateRecord : valida un registro completo (codigo, nombre, precio, stock)
; Entrada : ESI = inicio del registro.
; Salida  : CF=1 si es invalido.
; Modifica: EFLAGS (ESI se conserva)
; ============================================================================
ValidateRecord PROC USES eax esi
    call ValidateCode           ; codigo en offset 0
    jc   vr_bad
    add  esi, OFF_NAME
    call ValidateName
    jc   vr_bad
    sub  esi, OFF_NAME
    mov  eax, [esi+OFF_PRICE]
    cmp  eax, 1
    jb   vr_bad
    cmp  eax, MAX_PRICE
    ja   vr_bad
    mov  eax, [esi+OFF_STOCK]
    cmp  eax, MAX_STOCK
    ja   vr_bad
    clc
    jmp  vr_done
vr_bad:
    stc
vr_done:
    ret
ValidateRecord ENDP

; ============================================================================
; CodesEqual : compara los 7 caracteres de dos codigos.
; Entrada : ESI, EDI = codigos.
; Salida  : ZF=1 si son iguales.
; Modifica: EFLAGS
; ============================================================================
CodesEqual PROC USES eax ecx esi edi
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
    ret                         ; los POP del epilogo no alteran las banderas
CodesEqual ENDP

; ============================================================================
; FindProduct : busca un codigo en el catalogo (recorrido con ESI).
; Entrada : EDI = codigo (cadena).
; Salida  : CF=0 y ESI = registro encontrado; CF=1 si no existe.
; Modifica: ESI, EFLAGS
; ============================================================================
FindProduct PROC USES ecx
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
    ret
fp_found:
    clc
    ret
FindProduct ENDP

; ============================================================================
; ShowRecord : imprime un producto.
; Entrada : ESI = registro.
; Modifica: EFLAGS
; ============================================================================
ShowRecord PROC USES eax edx
    mov  edx, esi               ; codigo (offset 0)
    call WriteString
    Say  msgSep
    lea  edx, [esi+OFF_NAME]
    call WriteString
    Say  msgSep
    mov  eax, [esi+OFF_PRICE]
    call PrintMXN
    ShowU32 msgExist, [esi+OFF_STOCK]
    ret
ShowRecord ENDP

; ============================================================================
; AskProduct : pide un codigo, lo valida y lo localiza.
; Salida  : CF=0 y ESI = registro; CF=1 si hubo error (mensaje ya mostrado).
; Modifica: ESI, EFLAGS
; ============================================================================
AskProduct PROC USES eax edi        ; ESI es resultado -> fuera de USES
    AskCheck msgAskCode, ValidateCode, ap_badfmt, ap_err
    mov  edi, OFFSET inbuf
    call FindProduct
    jc   ap_nf
    clc
    ret
ap_badfmt:
    Fail msgBadCode
ap_nf:
    Fail msgNotFound
ap_err:
    stc
    ret
AskProduct ENDP

; ============================================================================
; AskQuantity : pide una cantidad entera 1..100.
; Salida  : EAX = cantidad; CF=1 si es invalida (mensaje ya mostrado).
; Modifica: EAX, EFLAGS (ESI, ECX y EDX se conservan)
; ============================================================================
AskQuantity PROC USES ecx edx esi
    Ask  msgAskQty
    jc   aq_err
    ParseBetween 1, MAX_STOCK
    jc   aq_inv
    ret                         ; ParseRange dejo CF=0
aq_inv:
    Fail msgBadQty
aq_err:
    stc
    ret
AskQuantity ENDP

; ============================================================================
; ConfirmYN : lee una respuesta S/N.
; Salida  : CF=0 si respondio S/s; CF=1 en cualquier otro caso.
; Modifica: EAX, EFLAGS
; ============================================================================
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

; ============================================================================
; ConfirmDiscard : si hay cambios sin guardar pide confirmacion.
; Salida  : CF=0 si se puede continuar; CF=1 si el usuario no confirma.
; Modifica: EAX, EFLAGS
; ============================================================================
ConfirmDiscard PROC
    cmp  dirty, 0
    je   cf_ok
    Say  msgUnsaved
    call ConfirmYN              ; CF=0 si respondio S
    ret
cf_ok:
    clc
    ret
ConfirmDiscard ENDP

; ============================================================================
; DoRegister : alta de producto. Todo se valida y se guarda en variables
;              temporales; el catalogo solo cambia al final (sin cambios
;              parciales).
; Modifica: EAX, EBX, ECX, EDX, ESI, EDI, EFLAGS
; ============================================================================
DoRegister PROC
    cmp  prodCount, PROD_MAX
    jb   dr_space
    Reject msgFull
dr_space:
    AskCheck msgAskCode, ValidateCode, dr_badcode, dr_end
    mov  edi, OFFSET inbuf
    call FindProduct
    jnc  dr_dup
    CopyField inbuf, tmpCode, CODE_SIZE
    AskCheck msgAskName, ValidateName, dr_badname, dr_end
    CopyField inbuf, tmpName, NAME_SIZE
    AskCheck msgAskPrice, ParsePrice, dr_badprice, dr_end
    mov  tmpPrice, eax
    Ask  msgAskStock
    jc   dr_end
    ParseBetween 0, MAX_STOCK
    jc   dr_badstock
    mov  tmpStock, eax
    ; --- confirmacion: se escribe el registro en la tabla ---
    RecAddr ebx, products, prodCount    ; EBX = registro destino
    CopyField tmpCode, [ebx], CODE_SIZE
    CopyField tmpName, [ebx+OFF_NAME], NAME_SIZE
    mov  eax, tmpPrice
    mov  [ebx+OFF_PRICE], eax
    mov  eax, tmpStock
    mov  [ebx+OFF_STOCK], eax
    inc  prodCount
    mov  dirty, 1
    Reject msgRegOk
dr_badcode:
    Reject msgBadCode
dr_dup:
    Reject msgDup
dr_badname:
    Reject msgBadName
dr_badprice:
    Reject msgBadPrice
dr_badstock:
    Say  msgBadStock
dr_end:
    ret
DoRegister ENDP

; ============================================================================
; DoShowAll : muestra el inventario recorriendo la tabla con ESI.
; Modifica: ECX, ESI, EFLAGS
; ============================================================================
DoShowAll PROC
    mov  ecx, prodCount
    test ecx, ecx
    jnz  sa_go
    Reject msgEmpty
sa_go:
    mov  esi, OFFSET products
sa_loop:
    call ShowRecord
    add  esi, REC_SIZE
    loop sa_loop
    ret
DoShowAll ENDP

; ============================================================================
; DoSearch : busca por codigo y muestra el producto.
; Modifica: ESI, EFLAGS
; ============================================================================
DoSearch PROC
    call AskProduct
    jc   ds_end
    call ShowRecord
ds_end:
    ret
DoSearch ENDP

; ============================================================================
; DoReceive : suma unidades a un producto existente (maximo 100).
; Modifica: EAX, ECX, ESI, EFLAGS
; ============================================================================
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
    ShowU32 msgRecvOk, ecx
    ret
rv_ovf:
    Reject msgOvf
rv_excess:
    Say  msgExcess
rv_end:
    ret
DoReceive ENDP

; ============================================================================
; CalcDiscount : regla de descuento por cantidad.
;   descuento = base*10/100 si cantidad>=10 (division entera: se descarta la
;               fraccion de centavo); 0 en otro caso.
; Entrada : EAX = importe base, EBX = cantidad.
; Salida  : EAX = descuento; CF=1 si desborda.
; Modifica: EAX, EFLAGS
; ============================================================================
CalcDiscount PROC USES ebx edx      ; EAX es resultado -> fuera de USES
    cmp  ebx, DISC_MIN_QTY
    jb   cd_none
    mov  ebx, DISC_PCT
    mul  ebx                    ; EDX:EAX = base*10 ; CF=1 si desborda
    jc   cd_end
    mov  ebx, 100
    div  ebx                    ; descuento entero (EDX=0 tras MUL sin acarreo)
    clc
    ret
cd_none:
    xor  eax, eax               ; descuento 0 y CF=0
cd_end:
    ret
CalcDiscount ENDP

; ============================================================================
; CalcSale : base = precio*cantidad; descuento; final = base - descuento.
; Entrada : ESI = registro del producto, EBX = cantidad.
; Salida  : ECX = base, EDI = descuento, EDX = final; CF=1 si desborda.
; Modifica: ECX, EDX, EDI, EFLAGS
; ============================================================================
CalcSale PROC USES eax              ; ECX, EDX, EDI son resultados
    mov  eax, [esi+OFF_PRICE]
    mul  ebx                    ; EDX:EAX = precio*cantidad
    jc   cs_end
    mov  ecx, eax               ; ECX = importe base
    call CalcDiscount           ; EAX = base -> EAX = descuento
    jc   cs_end
    mov  edi, eax               ; EDI = descuento
    mov  edx, ecx
    sub  edx, edi               ; EDX = importe final
    clc
cs_end:
    ret
CalcSale ENDP

; ============================================================================
; DoSell : venta de un solo producto con descuento por cantidad.
; Existencias e ingresos se modifican SOLO despues de pasar todas las pruebas.
; Modifica: EAX, EBX, ECX, EDX, ESI, EDI, EFLAGS
; ============================================================================
DoSell PROC
    call AskProduct
    jc   sl_end
    call ShowRecord
    call AskQuantity
    jc   sl_end
    mov  ebx, eax               ; EBX = cantidad
    cmp  ebx, [esi+OFF_STOCK]
    ja   sl_nostock
    call CalcSale               ; ECX = base, EDI = descuento, EDX = final
    jc   sl_ovf
    mov  eax, revenue
    add  eax, edx               ; nuevos ingresos
    jc   sl_ovf
    ; ---- todo valido: se confirma la venta ----
    mov  revenue, eax
    mov  eax, [esi+OFF_STOCK]
    sub  eax, ebx
    mov  [esi+OFF_STOCK], eax
    mov  dirty, 1
    ShowMXN msgBase, ecx
    test edi, edi
    jz   sl_nodisc
    ShowMXN msgDisc, edi
    jmp  sl_final
sl_nodisc:
    Say  msgNoDisc
sl_final:
    ShowMXN msgFinal, edx
    Reject msgSaleOk
sl_nostock:
    Reject msgNoStock
sl_ovf:
    Say  msgOvf
sl_end:
    ret
DoSell ENDP

; ============================================================================
; DoSummary : unidades, valor del inventario e ingresos de la sesion.
; Modifica: EAX, EBX, ECX, EDX, ESI, EDI, EFLAGS
; ============================================================================
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
    ShowU32 msgSumUnits, ebx
    ShowMXN msgSumValue, edi
    ShowMXN msgSumRev, revenue
    ret
sm_ovf:
    Reject msgOvf
DoSummary ENDP

; ============================================================================
; SaveCatalog : escribe fileHdr+prodCount+registros (8 + n*44 bytes).
; Salida  : CF=1 si fallo (CreateOutputFile, WriteToFile o CloseFile).
; Modifica: EAX, ECX, EDX, EFLAGS
; ============================================================================
SaveCatalog PROC
    mov  edx, OFFSET fileName
    call CreateOutputFile       ; EAX = handle o INVALID_HANDLE_VALUE
    cmp  eax, INVALID_HANDLE_VALUE
    je   sv_err
    mov  hFile, eax
    FileBytes eax, prodCount
    mov  expected, eax          ; bytes que se deben escribir
    mov  eax, hFile
    mov  edx, OFFSET fileHdr
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
    Fail msgSaveErr
SaveCatalog ENDP

; ============================================================================
; ReadInventoryFile : abre, lee a loadbuf y cierra inventario.dat.
; Valida: archivo existe, lectura sin error y 8 <= tamano <= 448.
; Salida  : CF=0 y bytesRead = tamano; CF=1 si fallo (mensaje ya mostrado).
; Modifica: EFLAGS (bytesRead, hFile y loadbuf son variables)
; ============================================================================
ReadInventoryFile PROC USES eax ecx edx edi
    mov  edx, OFFSET fileName
    call OpenInputFile
    cmp  eax, INVALID_HANDLE_VALUE
    je   ri_nofile
    mov  hFile, eax
    mov  edi, OFFSET loadbuf    ; limpia el buffer temporal
    mov  ecx, FILE_CAP + 1
    call ZeroMem
    mov  eax, hFile
    mov  edx, OFFSET loadbuf
    mov  ecx, FILE_CAP          ; capacidad (no es lo mismo que bytes leidos)
    call ReadFromFile           ; CF=1 si error; EAX = bytes leidos
    pushfd
    mov  bytesRead, eax
    mov  eax, hFile
    call CloseFile
    popfd
    jc   ri_readerr
    cmp  bytesRead, HDR_SIZE
    jb   ri_invalid
    cmp  bytesRead, FILE_CAP    ; 449 => el archivo excede lo permitido
    jae  ri_invalid
    clc
    ret
ri_nofile:
    Fail msgNoFile
ri_readerr:
    Fail msgReadErr
ri_invalid:
    Fail msgInvalid
ReadInventoryFile ENDP

; ============================================================================
; ValidateTable : valida cada registro leido en loadbuf+8.
; Entrada : EBX = numero de registros.
; Salida  : CF=1 si algun registro es invalido.
; Modifica: EFLAGS
; ============================================================================
ValidateTable PROC USES ecx esi
    mov  ecx, ebx
    mov  esi, OFFSET loadbuf + HDR_SIZE
    test ecx, ecx
    jz   vt_ok
vt_rec:
    call ValidateRecord
    jc   vt_bad
    add  esi, REC_SIZE
    loop vt_rec
vt_ok:
    clc
    ret
vt_bad:
    stc
    ret
ValidateTable ENDP

; ============================================================================
; HasDuplicates : busca codigos repetidos en loadbuf+8 (pares i<j).
; Entrada : EBX = numero de registros.
; Salida  : CF=1 si hay codigos repetidos.
; Modifica: EFLAGS
; ============================================================================
HasDuplicates PROC USES ecx edx esi edi
    mov  esi, OFFSET loadbuf + HDR_SIZE
    mov  ecx, ebx
hd_out:
    cmp  ecx, 1
    jbe  hd_none
    mov  edi, esi
    add  edi, REC_SIZE
    mov  edx, ecx
    dec  edx
hd_in:
    call CodesEqual
    je   hd_dup
    add  edi, REC_SIZE
    dec  edx
    jnz  hd_in
    add  esi, REC_SIZE
    dec  ecx
    jmp  hd_out
hd_none:
    clc
    ret
hd_dup:
    stc
    ret
HasDuplicates ENDP

; ============================================================================
; LoadCatalog : lee inventario.dat, VALIDA todo y solo entonces reemplaza el
;               catalogo. Si algo falla, no cambia nada.
; Validaciones: archivo existe, lectura sin error, tamano>=8 y <=448,
;   firma "INV1", conteo<=10, tamano == 8+conteo*44, cada registro valido,
;   sin codigos duplicados.
; Salida  : CF=1 si fallo.
; Modifica: EAX, EBX, ECX, EDX, ESI, EDI, EFLAGS
; ============================================================================
LoadCatalog PROC
    call ReadInventoryFile
    jc   ld_end                 ; mensaje ya mostrado
    cmp  DWORD PTR [loadbuf], MAGIC_INV1
    jne  ld_invalid
    mov  eax, DWORD PTR [loadbuf+4]
    cmp  eax, PROD_MAX
    ja   ld_invalid
    FileBytes edx, eax
    cmp  edx, bytesRead         ; tamano exacto esperado
    jne  ld_invalid
    mov  ebx, eax               ; EBX = conteo
    call ValidateTable
    jc   ld_invalid
    call HasDuplicates
    jc   ld_invalid
    cld
    mov  esi, OFFSET loadbuf + 4    ; conteo + registros
    mov  edi, OFFSET prodCount
    mov  ecx, 4 + PROD_MAX*REC_SIZE
    rep  movsb
    mov  dirty, 0
    Say  msgLoaded
    clc
ld_end:
    ret
ld_invalid:
    Fail msgInvalid
LoadCatalog ENDP

; ============================================================================
; DoLoad : opcion 8 del menu: confirma si hay cambios y carga el catalogo.
; Modifica: EAX, EBX, ECX, EDX, ESI, EDI, EFLAGS
; ============================================================================
DoLoad PROC
    call ConfirmDiscard
    jc   dl_end
    call LoadCatalog
dl_end:
    ret
DoLoad ENDP

; ============================================================================
; main : menu repetitivo. Antes de cada vuelta compara ESP con el valor
;        inicial para comprobar que la pila quedo equilibrada.
;        Las opciones 1..8 se despachan con la macro MenuItem.
; ============================================================================
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
    MenuItem '1', DoRegister
    MenuItem '2', DoShowAll
    MenuItem '3', DoSearch
    MenuItem '4', DoReceive
    MenuItem '5', DoSell
    MenuItem '6', DoSummary
    MenuItem '7', SaveCatalog
    MenuItem '8', DoLoad
    cmp  al, '9'
    jne  bad_opt
    call ConfirmDiscard         ; opcion 9: salir (pregunta si hay cambios)
    jc   menu_loop
    exit
bad_opt:
    Say  msgBadOpt
    jmp  menu_loop
stack_err:
    Say  msgStackErr
    exit
main ENDP
END main