# Parcial 2, problema 3: sopa de letras.
defmodule Sopa do
  @moduledoc "Valida palabras y las busca en una sopa de letras en ocho direcciones."
  @sopa Path.join(__DIR__, "sopa.txt")
  @palabras Path.join(__DIR__, "palabras.txt")
  @salida Path.join(__DIR__, "resultado_sopa.txt")

  @direcciones [
    {"derecha", 0, 1}, {"izquierda", 0, -1},
    {"abajo", 1, 0}, {"arriba", -1, 0},
    {"abajo-derecha", 1, 1}, {"abajo-izquierda", 1, -1},
    {"arriba-derecha", -1, 1}, {"arriba-izquierda", -1, -1}
  ]

  @doc "Lee sopa y palabras, escribe resultados y devuelve `:ok`."
  def main do
    File.write(@salida, "")

    cond do
      not File.exists?(@sopa) ->
        mostrar("Falta sopa.txt")

      not File.exists?(@palabras) ->
        mostrar("Falta palabras.txt")

      true ->
        filas = leer_sopa()
        palabras = leer_palabras()
        mapa = crear_mapa(filas)
        disponibles = contar_filas(filas, %{})

        encontradas =
          Enum.reduce(palabras, 0, fn palabra, total ->
            if procesar_palabra(palabra, filas, mapa, disponibles, @direcciones) do
              total + 1
            else
              total
            end
          end)

        mostrar("Palabras encontradas: #{encontradas} de #{length(palabras)}")
    end

    :ok
  end

  # leer_sopa/0: lee el archivo y devuelve filas de letras.
  # Limpia las líneas antes de construir la lista de filas.
  defp leer_sopa do
    @sopa
    |> File.stream!()
    |> Stream.map(fn linea -> limpiar(linea) end)
    |> Stream.filter(fn linea -> linea != "" and String.first(linea) != "#" end)
    |> Stream.map(fn linea -> String.graphemes(linea) end)
    |> Enum.to_list()
  end

  # leer_palabras/0: lee palabras no vacías y devuelve la lista sin repetidos.
  defp leer_palabras do
    @palabras
    |> File.stream!()
    |> Stream.map(fn linea -> linea |> limpiar() |> String.upcase() end)
    |> Stream.filter(fn linea -> linea != "" and String.first(linea) != "#" end)
    |> Enum.to_list()
    |> Enum.uniq()
  end

  # crear_mapa/1: recibe filas y devuelve un mapa de coordenadas a letras.
  defp crear_mapa(filas) do
    filas
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {letras, fila}, mapa ->
      letras
      |> Enum.with_index()
      |> Enum.reduce(mapa, fn {letra, columna}, resultado ->
        Map.put(resultado, {fila, columna}, letra)
      end)
    end)
  end

  # procesar_palabra/5: valida una palabra, busca sus formas y las informa;
  # devuelve true si encontró alguna forma y false en caso contrario.
  defp procesar_palabra(palabra, filas, mapa, disponibles, direcciones) do
    letras = String.graphemes(palabra)
    necesarias = contar_letras(letras, %{})
    faltan = faltantes(letras, necesarias, disponibles, %{}, [])
    mostrar("Palabra: #{palabra}")

    if faltan != [] do
      mostrar("Encontrada: No (descartada: #{motivo(faltan)})")
      mostrar("")
      false
    else
      formas = buscar_filas(filas, 0, letras, mapa, direcciones, [])

      if formas == [] do
        mostrar("Encontrada: No")
        mostrar("")
        false
      else
        unidad = if length(formas) == 1, do: "forma", else: "formas"
        mostrar("Encontrada: Sí (#{length(formas)} #{unidad})")
        informar_formas(formas, 1)
        mostrar("")
        true
      end
    end
  end

  # contar_filas/2: recibe filas y cantidades acumuladas; devuelve el mapa
  # de frecuencias. Con [] termina; con una fila cuenta sus letras y sigue.
  # Esta validación recursiva no usa Enum ni Stream.
  defp contar_filas([], cantidades), do: cantidades
  defp contar_filas([fila | resto], cantidades) do
    contar_filas(resto, contar_letras(fila, cantidades))
  end

  # contar_letras/2: recibe letras y cantidades; devuelve las frecuencias.
  # Con [] termina; con una letra la cuenta y continúa con el resto.
  defp contar_letras([], cantidades), do: cantidades
  defp contar_letras([letra | resto], cantidades) do
    nuevas = Map.update(cantidades, letra, 1, fn cantidad -> cantidad + 1 end)
    contar_letras(resto, nuevas)
  end

  # faltantes/5: recibe letras, cantidades necesarias y disponibles,
  # letras vistas y avisos; devuelve {letra, necesita, tiene} por cada falta.
  # Con [] termina; en cada paso revisa una letra y pasa el resto.
  defp faltantes([], _necesarias, _disponibles, _vistas, faltan), do: faltan
  defp faltantes([letra | resto], necesarias, disponibles, vistas, faltan) do
    if Map.get(vistas, letra, false) do
      faltantes(resto, necesarias, disponibles, vistas, faltan)
    else
      necesita = Map.get(necesarias, letra, 0)
      tiene = Map.get(disponibles, letra, 0)
      nuevas = if necesita > tiene, do: faltan ++ [{letra, necesita, tiene}], else: faltan
      faltantes(resto, necesarias, disponibles, Map.put(vistas, letra, true), nuevas)
    end
  end

  # motivo/1: recibe faltantes y devuelve el texto que explica el descarte.
  defp motivo(faltan) do
    if todas_ausentes(faltan),
      do: "la sopa no tiene #{letras_texto(faltan)}",
      else: "faltan letras o repeticiones: #{detalle_texto(faltan)}"
  end

  # todas_ausentes/1: true si ninguna letra faltante está en la sopa.
  defp todas_ausentes([]), do: true
  defp todas_ausentes([{_letra, _necesita, tiene} | resto]), do: tiene == 0 and todas_ausentes(resto)

  # letras_texto/1: une las letras faltantes con comas.
  defp letras_texto([{letra, _, _}]), do: letra
  defp letras_texto([{letra, _, _} | resto]), do: letra <> ", " <> letras_texto(resto)

  # detalle_texto/1: describe cuántas veces se necesita y hay cada letra.
  defp detalle_texto([{letra, necesita, tiene}]), do: "#{letra} (necesita #{necesita}, hay #{tiene})"
  defp detalle_texto([{letra, necesita, tiene} | resto]),
    do: "#{letra} (necesita #{necesita}, hay #{tiene}), " <> detalle_texto(resto)

  # buscar_filas/6: recibe filas, índice, palabra, mapa, direcciones y formas;
  # devuelve las formas. Con [] termina; con una fila busca y pasa el resto.
  # La búsqueda sigue por columnas, direcciones y letras con recursión.
  defp buscar_filas([], _fila, _palabra, _mapa, _direcciones, formas), do: formas
  defp buscar_filas([casillas | resto], fila, palabra, mapa, direcciones, formas) do
    nuevas = buscar_columnas(casillas, fila, 0, palabra, mapa, direcciones, [])
    buscar_filas(resto, fila + 1, palabra, mapa, direcciones, formas ++ nuevas)
  end

  # buscar_columnas/7: recibe letras de fila, coordenadas, palabra, mapa,
  # direcciones y formas; devuelve las formas. Con [] termina; en cada
  # columna prueba direcciones si coincide la primera letra y sigue.
  defp buscar_columnas([], _fila, _columna, _palabra, _mapa, _direcciones, formas), do: formas
  defp buscar_columnas([letra | resto], fila, columna, [primera | _] = palabra,
        mapa, direcciones, formas) do
    nuevas =
      if letra == primera do
        buscar_direcciones(direcciones, fila, columna, palabra, mapa, [])
      else
        []
      end

    buscar_columnas(resto, fila, columna + 1, palabra, mapa, direcciones, formas ++ nuevas)
  end

  # buscar_direcciones/6: recibe direcciones, inicio, palabra, mapa y formas;
  # devuelve las formas. Con [] termina; prueba una dirección y pasa el resto.
  defp buscar_direcciones([], _fila, _columna, _palabra, _mapa, formas), do: formas
  defp buscar_direcciones([{nombre, paso_fila, paso_columna} | resto],
        fila, columna, palabra, mapa, formas) do
    nuevas =
      case comparar(palabra, fila, columna, paso_fila, paso_columna, mapa, []) do
        {:ok, posiciones} ->
          [%{inicio: {fila, columna}, fin: ultima(posiciones),
             direccion: nombre, posiciones: posiciones}]
        :no -> []
      end

    buscar_direcciones(resto, fila, columna, palabra, mapa, formas ++ nuevas)
  end

  # comparar/7: recibe letras, fila y columna por separado, pasos de
  # dirección, mapa y posiciones. Devuelve {:ok, posiciones} si coinciden
  # todas, o :no. Con [] termina; con una letra avanza a la siguiente casilla.
  defp comparar([], _fila, _columna, _paso_fila, _paso_columna, _mapa, posiciones),
    do: {:ok, posiciones}

  defp comparar([letra | resto], fila, columna, paso_fila, paso_columna, mapa, posiciones) do
    if Map.get(mapa, {fila, columna}) == letra do
      comparar(resto, fila + paso_fila, columna + paso_columna,
        paso_fila, paso_columna, mapa, posiciones ++ [{fila, columna}])
    else
      :no
    end
  end

  # ultima/1: recibe posiciones no vacías y devuelve la última.
  # Con una termina; con más se llama con el resto.
  defp ultima([posicion]), do: posicion
  defp ultima([_ | resto]), do: ultima(resto)

  # informar_formas/2: recibe formas y número inicial; escribe cada forma.
  # Con [] devuelve :ok; en otro caso informa la primera y sigue con el resto.
  defp informar_formas([], _numero), do: :ok
  defp informar_formas([forma | resto], numero) do
    mostrar("Forma #{numero}: comienza en #{coordenada(forma.inicio)}, termina en #{coordenada(forma.fin)}, dirección #{forma.direccion}")
    recorrido = forma.posiciones
      |> Enum.map(fn posicion -> coordenada(posicion) end)
      |> Enum.join(" -> ")
    mostrar(recorrido)
    informar_formas(resto, numero + 1)
  end

  # coordenada/1: convierte {fila, columna} en texto.
  defp coordenada({fila, columna}), do: "{#{fila},#{columna}}"
  # limpiar/1: quita espacios y la marca BOM de una línea.
  defp limpiar(linea), do: linea |> String.replace("\uFEFF", "") |> String.trim()

  # mostrar/1: imprime una línea y la agrega al archivo de resultados.
  defp mostrar(linea) do
    IO.puts(linea)
    File.write(@salida, linea <> "\n", [:append])
  end
end

Sopa.main()
