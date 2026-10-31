# Proyecto Unidad 2 – Sistema Papelería 

**Negocio:** papelería. 
**Regla adicional:** descuento por cantidad (10 % del importe base si se venden ≥ 10 unidades; fracción de centavo descartada con división entera).
Administra el inventario y las ventas de una papelería, con guardado y carga del catálogo en un archivo.

> Toda la captura y la salida de números se resuelve con **conversiones propias** (`ReadString` / `WriteString`). No se usan `ReadDec`, `ReadInt`, `ParseDecimal32`, `WriteDec` ni `WriteHex`.

##  Funciones

| # | Opción | Descripción |
|---|---|---|
| 1 | Registrar producto | Alta con código `ABC-123`, nombre, precio y existencia. Rechaza duplicados y capacidad llena |
| 2 | Mostrar inventario | Lista todos los productos |
| 3 | Buscar por código | Localiza un producto |
| 4 | Recibir mercancía | Suma unidades sin pasar de 100 |
| 5 | Vender | Valida existencias, calcula el importe, aplica descuento y descuenta unidades |
| 6 | Resumen | Unidades disponibles, valor del inventario e ingresos de la sesión |
| 7 | Guardar | Escribe el catálogo en `inventario.dat` |
| 8 | Cargar | Lee y valida `inventario.dat` antes de reemplazar el catálogo |
| 9 | Salir | Avisa si hay cambios sin guardar |

El catálogo se carga automáticamente al iniciar si el archivo existe.

##  Regla adicional del negocio: descuento por cantidad

Si se venden **10 o más unidades** de un producto, se descuenta el **10 %** del importe base. La fracción de centavo se descarta (división entera).

| Caso | Cálculo | Resultado |
|---|---|---|
| 9 mochilas a $185.50 | 9 × 185.50 | $1669.50 (sin descuento) |
| 10 cuadernos a $45.50 | 455.00 − 45.50 | $409.50 (con descuento) |

##  Datos y límites

- Hasta **10 productos**.
- Código: 3 letras mayúsculas, guion y 3 dígitos (`ABC-123`), único.
- Nombre: 1 a 25 caracteres imprimibles (sin `;`).
- Precio: de $0.01 a $9999.99 MXN. Acepta pesos enteros o punto con 1 o 2 decimales; rechaza símbolos y separadores de miles. Se guarda internamente en **centavos enteros**.
- Existencia: 0 a 100. Entradas y ventas: enteros mayores que cero.
- Todos los importes se muestran con dos decimales y la etiqueta `MXN`.
- Se comprueban desbordamientos (`MUL`/`ADD` con bandera de acarreo) y una operación rechazada no modifica los datos anteriores.

##  Organización en memoria

Cada producto ocupa un registro de **44 bytes**; `ESI` recorre la tabla sumando 44 por producto.

| Offset | Tamaño | Campo |
|---|---|---|
| 0 | 8 | Código + `00h` |
| 8 | 26 | Nombre + `00h` (relleno con ceros) |
| 34 | 2 | Relleno de alineación |
| 36 | 4 | Precio en centavos (DWORD) |
| 40 | 4 | Existencia (DWORD) |

##  Formato de `inventario.dat`

Texto plano, editable en el Bloc de notas. Primera línea con la firma `INV1`; luego una línea por producto:

```
INV1
CUA-001;Cuaderno profesional;45.50;20
MOC-015;Mochila escolar;185.50;15
COR-789;Corrector liquido;12.05;8

Formato de línea: `CODIGO;Nombre;precio MXN;existencia`.
```


**Validaciones al cargar** (se interpreta a una tabla temporal y solo si todo es válido reemplaza el catálogo):
archivo existente, sin error de lectura, tamaño menor a la capacidad del buffer, firma `INV1`, máximo 10 productos, código/nombre/precio/existencia válidos (con las mismas rutinas de la captura) y sin códigos duplicados. Si el archivo falta o está dañado, se muestra un aviso y se conserva el catálogo actual.

##  Requisitos

- Windows con **Visual Studio 2019/2022** 
- **MASM** habilitado en el proyecto (*Build Customizations → masm*)
- Librería **Irvine32** configurada (plantilla de proyecto del curso)
- Plataforma de compilación: **x86** (32 bits)

##  Compilar y ejecutar

1. Abre la solución con la plantilla de Irvine32 en **x86 / Debug**.
2. Deja `Papeleria.asm` como único archivo fuente (excluye cualquier otro `main`).
3. Copia `inventario.dat` a la carpeta de trabajo (por defecto, la carpeta del proyecto; verifica *Propiedades → Depuración → Directorio de trabajo = `$(ProjectDir)`*).
4. Ejecuta con **Ctrl+F5**. Al iniciar debe aparecer `Catalogo cargado correctamente`.

##  Estructura del código

| Procedimiento | Función |
|---|---|
| `ReadLine`, `GetInput` | Captura con `ReadString`, rechaza vacío y exceso de longitud |
| `ParseUInt`, `ParsePrice` | Cadena → entero / centavos con validación |
| `PrintU32`, `PrintMXN` | Entero → cadena decimal (cociente y residuo) y formato `$ 0.00 MXN` |
| `ValidateCode`, `ValidateName`, `CodesEqual`, `FindProduct` | Validación y búsqueda |
| `DoRegister`, `DoReceive`, `DoSell`, `DoSummary`, `DoShowAll`, `DoSearch` | Opciones del menú |
| `SaveCatalog`, `LoadCatalog`, `ReadField` | Archivo de inventario |
| `main` | Menú repetitivo; compara `ESP` en cada vuelta para verificar que la pila quede equilibrada |

Cada procedimiento documenta su entrada, salida y registros modificados, y conserva los registros que no son de salida.

## Pruebas sugeridas

- Alta válida y duplicada; códigos y precios inválidos (`12.345`, `$12`, `1,200`, `.5`, `5.`).
- Búsqueda existente e inexistente.
- Entrada de mercancía válida y que excede 100.
- Venta aceptada, con y sin descuento, y venta sin existencias suficientes.
- Resumen, guardar, cerrar y volver a ejecutar para recuperar el catálogo.
- Archivo ausente, firma alterada, precio inválido o código repetido dentro del archivo.

##  Notas

- Proyecto académico. Revisa las fuentes y el informe de entrega por separado.
- Los mensajes de consola están escritos sin acentos para evitar problemas de codificación en la consola de Windows.

## Fuentes consultadas

- Microsoft Learn. *Referencia de Microsoft Macro Assembler*. https://learn.microsoft.com/es-es/cpp/assembler/masm/microsoft-macro-assembler-reference?view=msvc-170
- Ricardev. *Ensamblador* (pila, push/pop, ESP). https://ricardev.gitbook.io/red-team/pwn-linux/teoria/ensamblador
- E0N Productions. *Taller ASM* (pila y CALL). https://ns2.elhacker.net/descargas/manuales/Lenguajes%20de%20Programacion/Ensamblador/Taller%20ASM%20-%20E0N%20Productions.pdf
- Referencia de la instrucción DIV (basada en el manual de Intel). https://www.felixcloutier.com/x86/div.html
- Jorgensen, E. *x86-64 Assembly Language Programming with Ubuntu*, cap. 10 (conversión de entero a cadena). https://eng.libretexts.org/Bookshelves/Computer_Science/Programming_Languages/x86-64_Assembly_Language_Programming_with_Ubuntu_(Jorgensen)/10%3A_Program_Development/10.03%3A_Implement_the_Program
¿

## Licencia

Proyecto con fines educativos.
