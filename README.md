#  Sistema de Ventas e Inventario - Papelería 

Proyecto académico desarrollado en **MASM x86 (32 bits)** utilizando la librería **Irvine32**, enfocado en la gestión de inventario, control de existencias, procesamiento de ventas con reglas de negocio, persistencia en archivos binarios y optimización de código mediante **procedimientos, macros con `LOCAL`, y la directiva `USES`**.

---

##  Características y Mejoras (Unidad 3)

Esta versión implementa optimizaciones estructurales clave para maximizar la legibilidad y reducir la redundancia respecto a la Unidad 2:
1. **Procedimientos Modularizados:** Tareas críticas como captura, validación de códigos y nombres, conversión de cadenas y manejo de archivos están aisladas en procedimientos independientes.
2. **Macros Parametrizadas con `LOCAL`:** Se implementaron macros eficientes (`Say`, `Fail`, `Ask`, `ShowMXN`, `ShowU32`, `CopyField`, `RecAddr`, `MenuItem`) para simplificar secuencias repetitivas, utilizando etiquetas locales (`LOCAL`) para evitar colisiones en las expansiones del preprocesador.
3. **Optimización con `USES`:** Adopción de la directiva `USES` en las cabeceras de los procedimientos para gestionar de forma limpia la preservación de registros en la pila, protegiendo adecuadamente los registros de retorno (`EAX`, `ESI`).
4. **Verificación de Pila:** El programa monitorea constantemente el puntero de pila (`ESP`) al inicio de cada ciclo del menú principal para garantizar un balance perfecto y prevenir desbordamientos.

---

##  Reglas del Negocio y Límites

* **Capacidad:** Hasta **10 productos** en el catálogo activo.
* **Código:** Formato exacto `ABC-123` (3 letras mayúsculas, un guion y 3 dígitos), único en el inventario.
* **Nombre:** De 1 a 25 caracteres ASCII imprimibles.
* **Precio:** De `$0.01` a `$9999.99` MXN. Se procesa internamente como **centavos enteros (`DWORD`)**.
* **Existencia:** De 0 a 100 unidades por producto.
* **Regla de Descuento por Cantidad:** Si se venden **10 o más unidades** de un mismo producto, se aplica automáticamente un **10% de descuento** sobre el importe base. Las fracciones de centavo se descartan mediante división entera (`DIV`).

---

##  Estructura de Datos y Persistencia (`inventario.dat`)

El sistema almacena el catálogo en un archivo binario estructurado con una firma inicial y bloques de registros fijos de **44 bytes** por producto:

| Offset | Tamaño | Campo |
| :--- | :--- | :--- |
| `0` | 8 bytes | Código + terminador `00h` (`"ABC-123",0`) |
| `8` | 26 bytes | Nombre + relleno con ceros |
| `34` | 2 bytes | Relleno de alineación |
| `36` | 4 bytes (`DWORD`) | Precio en centavos |
| `40` | 4 bytes (`DWORD`) | Existencia actual |

Al iniciar el programa, se intenta cargar automáticamente `inventario.dat` aplicando rigurosas validaciones de integridad (firma `"INV1"`, conteo de productos, validación de registros individuales y detección de códigos duplicados).

---

##  Requisitos de Compilación y Ejecución

1. **Entorno:** Sistema operativo Windows con **Visual Studio 2019 o 2022**.
2. **Configuración de Ensamblador:** Habilitar **MASM** en el proyecto (*Build Customizations → masm*).
3. **Librería:** Configurar la librería **Irvine32** en las propiedades del proyecto del curso.
4. **Arquitectura:** Plataforma de compilación configurada estrictamente a **x86 (32 bits)**.

---

##  Menú Principal de Opciones

1. **Registrar producto:** Alta validando formato, duplicados y capacidad máxima.
2. **Mostrar inventario:** Lista detallada de todos los productos activos.
3. **Buscar por código:** Localiza un producto y muestra sus datos formateados.
4. **Recibir mercancía:** Incrementa el stock de un producto (límite máximo de 100).
5. **Vender:** Valida stock, calcula importes, aplica el descuento por cantidad si corresponde y actualiza existencias e ingresos.
6. **Resumen:** Muestra el total de unidades disponibles, el valor monetario del inventario y los ingresos acumulados de la sesión.
7. **Guardar:** Escribe y actualiza el catálogo en `inventario.dat`.
8. **Cargar:** Lee y valida el archivo externo para reemplazar el catálogo actual (con advertencia de cambios sin guardar).
9. **Salir:** Cierra el sistema notificando si existen cambios pendientes de guardar.

---

##  Tabla de Pruebas (Unidad 3)

| Caso de Prueba | Descripción / Acción | Entrada de Datos | Resultado Esperado | Resultado Obtenido | Estatus |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Alta Válida** | Registrar un nuevo producto con datos correctos. | Código: `CUA-001`<br>Nombre: `Cuaderno`<br>Precio: `45.50`<br>Stock: `20` | Mensaje de éxito (`Producto registrado`). Catálogo actualizado y marcado como modificado (`dirty = 1`). | Mensaje de éxito, registro guardado correctamente en memoria. | **Aprobado** |
| **2. Alta Duplicada** | Intentar registrar un producto con un código ya existente. | Código: `CUA-001`<br>*(demás datos válidos)* | Rechazo del alta con mensaje de código duplicado (`Codigo duplicado. Operacion rechazada.`). | Se rechazó la operación sin sobrescribir el registro previo. | **Aprobado** |
| **3. Búsqueda Existente** | Localizar un producto mediante su código en el catálogo. | Opción `3`<br>Código: `CUA-001` | Muestra en pantalla el código, nombre, precio formateado y existencia actual del producto. | Despliegue correcto de los datos del producto solicitado. | **Aprobado** |
| **4. Entrada de Mercancía** | Sumar existencias a un producto sin superar el límite. | Opción `4`<br>Código: `CUA-001`<br>Cantidad: `15` | Actualiza la existencia sumando las unidades y muestra el stock actual. Marcado con `dirty = 1`. | Stock actualizado correctamente a 35 unidades. | **Aprobado** |
| **5. Venta con Descuento** | Vender 10 o más unidades aplicando la regla de negocio. | Opción `5`<br>Código: `CUA-001`<br>Cantidad: `10` (@ $45.50) | Importe base: `$455.00`<br>Descuento 10%: `-$45.50`<br>Importe final: `$409.50`<br>Venta aceptada. | Descuento aplicado correctamente descartando fracciones de centavo mediante división entera. | **Aprobado** |
| **6. Venta Rechazada (Stock Insuficiente)** | Intentar vender más unidades de las disponibles. | Opción `5`<br>Código: `CUA-001`<br>Cantidad: `50` | Rechazo de la venta con el mensaje de existencias insuficientes. Stock y saldo intactos. | Operación rechazada sin alterar las existencias en inventario. | **Aprobado** |
| **7. Resumen de Sesión** | Consultar el estado global del negocio. | Opción `6` | Despliegue de unidades totales disponibles, valor total monetario del inventario e ingresos acumulados. | Cálculo correcto y mostrado con el formato monetario MXN. | **Aprobado** |
| **8. Carga y Persistencia** | Guardar en disco y recargar el archivo binario. | Opción `7` (Guardar)<br>Opción `8` (Cargar / Reinicio) | Lectura exitosa de `inventario.dat`, validación de firma `"INV1"`, integridad de registros y carga sin errores. | Catálogo recuperado fielmente desde el archivo binario externo. | **Aprobado** |

---

##  Fuentes Consultadas

* Microsoft Learn. *Referencia de Microsoft Macro Assembler*. https://learn.microsoft.com/es-es/cpp/assembler/masm/microsoft-macro-assembler-reference?view=msvc-170
* Ricardev. *Ensamblador* (pila, push/pop, ESP). https://ricardev.gitbook.io/red-team/pwn-linux/teoria/ensamblador
* E0N Productions. *Taller ASM* (pila y CALL). https://ns2.elhacker.net/descargas/manuales/Lenguajes%20de%20Programacion/Ensamblador/Taller%20ASM%20-%20E0N%20Productions.pdf
* Referencia de la instrucción DIV (basada en el manual de Intel). https://www.felixcloutier.com/x86/div.html
* Jorgensen, E. *x86-64 Assembly Language Programming with Ubuntu*, cap. 10 (conversión de entero a cadena). https://eng.libretexts.org/Bookshelves/Computer_Science/Programming_Languages/x86-64_Assembly_Language_Programming_with_Ubuntu_(Jorgensen)/10%3A_Program_Development/10.03%3A_Implement_the_Program
