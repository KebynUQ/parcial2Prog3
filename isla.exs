# Parcial 2, problema 2: escapar de la isla.
defmodule Terreno do
  @moduledoc "Guarda el símbolo, nombre, costo y posibilidad de paso de un terreno."
  defstruct simbolo: "", nombre: "", transitable: false, costo: 0
end

defmodule Ruta do
  @moduledoc "Guarda las posiciones recorridas y el costo de una ruta."
  defstruct posiciones: [], costo: 0
end

defmodule Isla do
  @moduledoc "Valida el mapa de la isla y busca rutas desde el inicio hasta el bote."
  @mapa Path.join(__DIR__, "isla.txt")
  @terrenos Path.join(__DIR__, "terrenos.csv")
  @validacion Path.join(__DIR__, "validacion_isla.txt")
  @rutas Path.join(__DIR__, "rutas_isla.csv")
  @resumen Path.join(__DIR__, "resumen_isla.txt")

  @doc "Lee los archivos, registra errores o rutas y devuelve `:ok`."
  def main do
    File.write(@validacion, "")
    File.write(@rutas, "")
    File.write(@resumen, "")

    if File.exists?(@mapa) and File.exists?(@terrenos) do
      {terrenos, problemas_terrenos} = leer_terrenos()
      filas = leer_isla()
      inicio = buscar_simbolo(terrenos, "inicio")
      bote = buscar_simbolo(terrenos, "bote")
      agua = buscar_simbolo(terrenos, "agua")

      faltantes = revisar_terrenos([{"inicio", inicio}, {"bote", bote}, {"agua", agua}], [])

      {problemas_mapa, personas, botes} = validar(filas, terrenos, inicio, bote, agua)
      problemas = problemas_terrenos ++ faltantes ++ problemas_mapa

      if problemas != [] do
        Enum.each(problemas, fn problema ->
          IO.puts(problema)
          escribir(@validacion, problema)
        end)

        escribir(@resumen, "La isla es inválida; no se buscaron rutas.")
      else
        escribir(@validacion, "La isla es válida")
        IO.puts("La isla es válida")
        [origen] = personas
        [destino] = botes
        casillas = construir_casillas(filas)
        rutas = buscar(origen, destino, [origen], 0, casillas, terrenos)
        informar_rutas(rutas, filas, inicio, bote)
      end
    else
      mensaje = "Falta isla.txt o terrenos.csv"
      IO.puts(mensaje)
      escribir(@validacion, mensaje)
      escribir(@resumen, mensaje)
    end

    :ok
  end

  # leer_terrenos/0: lee el CSV y devuelve {terrenos, errores}.
  defp leer_terrenos do
    @terrenos
    |> File.stream!()
    |> Stream.with_index(1)
    |> Stream.map(fn {linea, numero} -> {limpiar(linea), numero} end)
    |> Stream.filter(fn {linea, _} -> linea != "" and String.first(linea) != "#" end)
    |> Stream.map(fn {linea, numero} -> {parse_terreno(linea), numero} end)
    |> Enum.reduce({%{}, []}, fn {resultado, numero}, {terrenos, errores} ->
      case resultado do
        {:ok, terreno} ->
          if Map.get(terrenos, terreno.simbolo) == nil do
            {Map.put(terrenos, terreno.simbolo, terreno), errores}
          else
            {terrenos, errores ++ ["Línea #{numero} de terrenos: símbolo repetido #{terreno.simbolo}"]}
          end

        {:error, motivo} ->
          {terrenos, errores ++ ["Línea #{numero} de terrenos: #{motivo}"]}
      end
    end)
  end

  # parse_terreno/1: convierte una línea CSV en {:ok, terreno} o {:error, motivo}.
  defp parse_terreno(linea) do
    case String.split(linea, ",") do
      [simbolo, nombre, transitable, costo_texto] ->
        simbolo = String.trim(simbolo)
        nombre = String.trim(nombre)
        transitable = String.trim(transitable)

        cond do
          simbolo == "" ->
            {:error, "símbolo vacío"}

          nombre == "" ->
            {:error, "nombre vacío"}

          transitable != "si" and transitable != "no" ->
            {:error, "transitable debe ser si o no"}

          true ->
            case Integer.parse(String.trim(costo_texto)) do
              {costo, ""} when costo >= 0 ->
                {:ok, %Terreno{simbolo: simbolo, nombre: nombre,
                  transitable: transitable == "si", costo: costo}}

              {_costo, ""} ->
                {:error, "costo negativo"}

              _ ->
                {:error, "costo no numérico"}
            end
        end

      _ ->
        {:error, "se esperaban cuatro campos"}
    end
  end

  # leer_isla/0: lee el mapa y devuelve una lista de filas de símbolos.
  defp leer_isla do
    @mapa
    |> File.stream!()
    |> Stream.map(fn linea -> limpiar(linea) end)
    |> Stream.filter(fn linea -> linea != "" and String.first(linea) != "#" end)
    |> Stream.map(fn linea -> String.split(linea) end)
    |> Enum.to_list()
  end

  # buscar_simbolo/2: recibe el mapa de terrenos y un nombre;
  # devuelve su símbolo o nil por medio de buscar_simbolo_lista/3.
  defp buscar_simbolo(terrenos, nombre) do
    buscar_simbolo_lista(Map.values(terrenos), nombre, nil)
  end

  # buscar_simbolo_lista/3: recorre terrenos, nombre y último símbolo hallado.
  # Con [] devuelve el acumulado; con un terreno actualiza y pasa el resto.
  defp buscar_simbolo_lista([], _nombre, encontrado), do: encontrado
  defp buscar_simbolo_lista([terreno | resto], nombre, encontrado) do
    nuevo = if terreno.nombre == nombre, do: terreno.simbolo, else: encontrado
    buscar_simbolo_lista(resto, nombre, nuevo)
  end

  # revisar_terrenos/2: recibe nombres con sus símbolos y avisos acumulados.
  # Con [] devuelve avisos; en cada paso agrega faltantes y pasa el resto.
  defp revisar_terrenos([], errores), do: errores
  defp revisar_terrenos([{nombre, simbolo} | resto], errores) do
    nuevos = if simbolo == nil,
      do: errores ++ ["Falta el terreno #{nombre} en terrenos.csv"],
      else: errores
    revisar_terrenos(resto, nuevos)
  end

  # validar/5: recibe filas, terrenos y símbolos de inicio, bote y agua;
  # devuelve {problemas, personas, botes}. Si no hay filas, informa el error.
  # El recorrido recursivo del mapa no usa Enum ni Stream.
  defp validar([], _terrenos, _inicio, _bote, _agua), do: {["La isla está vacía"], [], []}

  defp validar([primera | _] = filas, terrenos, inicio, bote, agua) do
    ancho = length(primera)
    alto = length(filas)
    {personas, botes, problemas} =
      validar_filas(filas, 0, ancho, alto, terrenos, inicio, bote, agua, [], [], [])

    problemas = if length(personas) == 1, do: problemas,
      else: problemas ++ ["Hay #{length(personas)} posiciones iniciales #{inicio}: #{posiciones_texto(personas)}"]
    problemas = if length(botes) == 1, do: problemas,
      else: problemas ++ ["Hay #{length(botes)} botes #{bote}: #{posiciones_texto(botes)}"]
    {problemas, personas, botes}
  end

  # validar_filas/11: recibe filas, medidas, símbolos y acumuladores;
  # devuelve {personas, botes, problemas}. Con [] termina; de otro modo
  # valida una fila con validar_casillas/12 y continúa con las restantes.
  defp validar_filas([], _fila, _ancho, _alto, _terrenos, _inicio, _bote, _agua,
        personas, botes, problemas), do: {personas, botes, problemas}

  defp validar_filas([casillas | resto], fila, ancho, alto, terrenos, inicio, bote, agua,
        personas, botes, problemas) do
    largo = length(casillas)
    problemas = if largo == ancho, do: problemas,
      else: problemas ++ ["Fila #{fila}: tiene #{largo} posiciones; se esperaban #{ancho}"]

    {personas, botes, problemas} =
      validar_casillas(casillas, fila, 0, largo, alto, terrenos, inicio, bote, agua,
        personas, botes, problemas)

    validar_filas(resto, fila + 1, ancho, alto, terrenos, inicio, bote, agua,
      personas, botes, problemas)
  end

  # validar_casillas/12: recibe casillas, medidas, símbolos y acumuladores;
  # devuelve {personas, botes, problemas}. Con [] termina; en cada paso
  # revisa símbolo y borde, aumenta columna y continúa con el resto.
  defp validar_casillas([], _fila, _columna, _largo, _alto, _terrenos, _inicio, _bote, _agua,
        personas, botes, problemas), do: {personas, botes, problemas}

  defp validar_casillas([simbolo | resto], fila, columna, largo, alto, terrenos, inicio, bote, agua,
        personas, botes, problemas) do
    posicion = {fila, columna}
    personas = if simbolo == inicio, do: personas ++ [posicion], else: personas
    botes = if simbolo == bote, do: botes ++ [posicion], else: botes

    problemas =
      if Map.get(terrenos, simbolo) == nil do
        problemas ++ ["Posición #{posicion_texto(posicion)}: símbolo desconocido #{simbolo}"]
      else
        problemas
      end

    borde = fila == 0 or fila == alto - 1 or columna == 0 or columna == largo - 1
    problemas =
      if agua != nil and borde and simbolo != agua do
        problemas ++ ["Posición #{posicion_texto(posicion)}: el borde debe ser agua y contiene #{simbolo}"]
      else
        problemas
      end

    validar_casillas(resto, fila, columna + 1, largo, alto, terrenos, inicio, bote, agua,
      personas, botes, problemas)
  end

  # posiciones_texto/1: recibe coordenadas y devuelve texto separado con
  # comas y "y" antes de la última. Las listas de 0, 1 o 2 son casos base.
  defp posiciones_texto([]), do: "ninguna"
  defp posiciones_texto([posicion]), do: posicion_texto(posicion)
  defp posiciones_texto([primera, segunda]),
    do: posicion_texto(primera) <> " y " <> posicion_texto(segunda)
  defp posiciones_texto([posicion | resto]), do: posicion_texto(posicion) <> ", " <> posiciones_texto(resto)
  # posicion_texto/1: convierte una coordenada {fila, columna} en texto.
  defp posicion_texto({fila, columna}), do: "{#{fila},#{columna}}"

  # construir_casillas/1: pasa las filas a un mapa de coordenadas y símbolos.
  defp construir_casillas(filas) do
    filas
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {casillas, fila}, mapa ->
      casillas
      |> Enum.with_index()
      |> Enum.reduce(mapa, fn {simbolo, columna}, resultado ->
        Map.put(resultado, {fila, columna}, simbolo)
      end)
    end)
  end

  # buscar/6: recibe posición, bote, visitadas, costo, casillas y terrenos;
  # devuelve rutas. Al llegar al bote crea una Ruta; en otro caso prueba
  # vecinos transitables no visitados y termina al agotar las ramas.
  defp buscar(destino, destino, visitadas, costo, _casillas, _terrenos) do
    [%Ruta{posiciones: visitadas, costo: costo}]
  end

  defp buscar({fila, columna}, destino, visitadas, costo, casillas, terrenos) do
    vecinos = [{fila - 1, columna}, {fila + 1, columna},
      {fila, columna - 1}, {fila, columna + 1}]

    Enum.reduce(vecinos, [], fn posicion, rutas ->
      simbolo = Map.get(casillas, posicion)

      cond do
        simbolo == nil or Enum.any?(visitadas, fn anterior -> anterior == posicion end) ->
          rutas

        true ->
          case Map.get(terrenos, simbolo) do
            %Terreno{transitable: false} -> rutas
            %Terreno{transitable: true, costo: nuevo_costo} ->
              rutas ++ buscar(posicion, destino, visitadas ++ [posicion],
                costo + nuevo_costo, casillas, terrenos)
          end
      end
    end)
  end

  # informar_rutas/4: recibe rutas, filas y símbolos de inicio y bote;
  # escribe rutas, resumen y mapa marcado; devuelve :ok.
  defp informar_rutas(rutas, filas, inicio, bote) do
    escribir(@rutas, "ruta;movimientos;costo;recorrido")

    rutas
    |> Enum.with_index(1)
    |> Enum.each(fn {ruta, numero} ->
      recorrido = Enum.map(ruta.posiciones, fn posicion -> posicion_texto(posicion) end)
        |> Enum.join(" -> ")
      movimientos = length(ruta.posiciones) - 1
      IO.puts("Ruta #{numero}: #{recorrido}; movimientos: #{movimientos}; costo: #{ruta.costo}")
      escribir(@rutas, "#{numero};#{movimientos};#{ruta.costo};#{recorrido}")
    end)

    escribir(@resumen, "Número total de rutas: #{length(rutas)}")
    IO.puts("Número total de rutas: #{length(rutas)}")

    if rutas == [] do
      escribir(@resumen, "No hay rutas hasta el bote.")
      IO.puts("No hay rutas hasta el bote.")
    else
      [corta | _] = Enum.sort_by(rutas, fn ruta -> length(ruta.posiciones) end)
      [barata | _] = Enum.sort_by(rutas, fn ruta -> ruta.costo end)
      cortas = Enum.filter(rutas, fn ruta -> length(ruta.posiciones) == length(corta.posiciones) end)

      Enum.each(cortas, fn ruta ->
        linea = "Ruta más corta: #{length(ruta.posiciones) - 1} movimientos; #{recorrido_texto(ruta.posiciones)}"
        IO.puts(linea)
        escribir(@resumen, linea)
      end)

      linea = "Ruta de menor costo: costo #{barata.costo} (#{length(barata.posiciones) - 1} movimientos); #{recorrido_texto(barata.posiciones)}"
      IO.puts(linea)
      escribir(@resumen, linea)
      escribir(@resumen, "Mapa con la ruta de menor costo:")

      filas
      |> Enum.with_index()
      |> Enum.each(fn {casillas, fila} ->
        texto = casillas
          |> Enum.with_index()
          |> Enum.map(fn {simbolo, columna} ->
            posicion = {fila, columna}
            if simbolo != inicio and simbolo != bote and
                Enum.any?(barata.posiciones, fn visitada -> visitada == posicion end),
              do: "*", else: simbolo
          end)
          |> Enum.join(" ")
        escribir(@resumen, texto)
      end)
    end

    :ok
  end

  # recorrido_texto/1: une una lista de posiciones en una cadena.
  defp recorrido_texto(posiciones) do
    posiciones |> Enum.map(fn posicion -> posicion_texto(posicion) end) |> Enum.join(" -> ")
  end

  # limpiar/1: quita espacios y la marca BOM de una línea.
  defp limpiar(linea), do: linea |> String.replace("\uFEFF", "") |> String.trim()

  # escribir/2: añade una línea con salto al archivo indicado.
  defp escribir(archivo, linea), do: File.write(archivo, linea <> "\n", [:append])
end

Isla.main()
