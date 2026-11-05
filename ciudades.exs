# Parcial 2, problema 1: rutas entre ciudades.
defmodule Conexion do
  @moduledoc "Guarda una conexión entre dos ciudades y sus datos de origen."
  defstruct origen: "", destino: "", distancia: 0, numero: 0, texto: ""

  @doc "Recibe una línea CSV y devuelve `{:ok, conexion}` o `{:error, motivo}`."
  def parse(linea) do
    case String.split(linea, ",") do
      [origen, destino, distancia_texto] ->
        origen = String.trim(origen)
        destino = String.trim(destino)

        if origen == "" or destino == "" do
          {:error, "ciudad vacía"}
        else
          case Integer.parse(String.trim(distancia_texto)) do
            {distancia, ""} when distancia >= 0 ->
              {:ok, %Conexion{origen: origen, destino: destino, distancia: distancia}}

            _ ->
              case Float.parse(String.trim(distancia_texto)) do
                {distancia, ""} when distancia >= 0 ->
                  {:ok, %Conexion{origen: origen, destino: destino, distancia: distancia}}

                _ ->
                  {:error, "distancia no numérica o negativa"}
              end
          end
        end

      _ ->
        {:error, "se esperaban ciudad_a,ciudad_b,distancia"}
    end
  end
end

defmodule Ruta do
  @moduledoc "Guarda las ciudades recorridas y la distancia total de una ruta."
  defstruct ciudades: [], distancia: 0
end

defmodule Ciudades do
  @moduledoc "Lee conexiones y consultas, valida los datos y busca rutas entre ciudades."
  @conexiones Path.join(__DIR__, "conexiones.csv")
  @consultas Path.join(__DIR__, "consultas.txt")
  @errores Path.join(__DIR__, "errores_conexiones.txt")
  @depuracion Path.join(__DIR__, "depuracion_conexiones.txt")
  @alcance Path.join(__DIR__, "alcance.txt")
  @salida Path.join(__DIR__, "rutas_encontradas.txt")

  @doc "Lee las entradas, escribe los resultados y devuelve `:ok`."
  def main do
    # Los archivos de salida se reemplazan al comenzar cada ejecución.
    File.write(@errores, "")
    File.write(@depuracion, "")
    File.write(@alcance, "")
    File.write(@salida, "")

    if File.exists?(@conexiones) and File.exists?(@consultas) do
      conexiones = leer_conexiones()
      {buenas, descartadas} = depurar(conexiones, [], [], [])
      Enum.each(descartadas, fn aviso -> escribir(@depuracion, aviso) end)
      grafo = construir_grafo(buenas)

      @consultas
      |> File.stream!()
      |> Stream.with_index(1)
      |> Stream.map(fn {linea, numero} -> {limpiar(linea), numero} end)
      |> Stream.filter(fn {linea, _} -> linea != "" and String.first(linea) != "#" end)
      |> Stream.map(fn {linea, numero} -> {String.split(linea, ","), linea, numero} end)
      |> Enum.each(fn {campos, linea, numero} ->
        resolver_consulta(campos, linea, numero, grafo)
      end)
    else
      mensaje = "Falta conexiones.csv o consultas.txt"
      IO.puts(mensaje)
      escribir(@salida, mensaje)
    end

    :ok
  end

  # leer_conexiones/0: lee el CSV y devuelve las conexiones válidas;
  # escribe los errores indicando el número original de línea.
  defp leer_conexiones do
    @conexiones
    |> File.stream!()
    |> Stream.with_index(1)
    |> Stream.map(fn {linea, numero} -> {limpiar(linea), numero} end)
    |> Stream.filter(fn {linea, _} -> linea != "" and String.first(linea) != "#" end)
    |> Stream.map(fn {linea, numero} ->
      case Conexion.parse(linea) do
        {:ok, conexion} -> {:ok, %{conexion | numero: numero, texto: linea}}
        {:error, motivo} -> {:error, numero, linea, motivo}
      end
    end)
    |> Enum.reduce([], fn resultado, validas ->
      case resultado do
        {:ok, conexion} ->
          validas ++ [conexion]

        {:error, numero, linea, motivo} ->
          escribir(@errores, "Línea #{numero}: #{linea} -> #{motivo}")
          validas
      end
    end)
  end

  # depurar/4: recibe pendientes, vistas, buenas y avisos; devuelve
  # {buenas, avisos}. Con [] termina; con una conexión revisa y pasa el resto.
  # Esta validación recursiva no usa Enum ni Stream.
  defp depurar([], _vistas, buenas, avisos), do: {buenas, avisos}

  defp depurar([conexion | resto], vistas, buenas, avisos) do
    cond do
      conexion.origen == conexion.destino ->
        aviso =
          "Línea #{conexion.numero}: #{conexion.texto} -> conecta una ciudad consigo misma; se descarta"

        depurar(resto, vistas, buenas, avisos ++ [aviso])

      true ->
        case anterior(conexion, vistas) do
          nil ->
            depurar(resto, vistas ++ [conexion], buenas ++ [conexion], avisos)

          previa ->
            aviso =
              if previa.distancia == conexion.distancia do
                "Línea #{conexion.numero}: #{conexion.texto} -> repetida (línea #{previa.numero}); se descarta"
              else
                "Línea #{conexion.numero}: #{conexion.texto} -> distancia distinta a la de la línea #{previa.numero} (#{previa.distancia}); se conserva la de la línea #{previa.numero}"
              end

            depurar(resto, vistas, buenas, avisos ++ [aviso])
        end
    end
  end

  # anterior/2: busca una conexión del mismo par de ciudades en vistas.
  # Con [] devuelve nil; si no coincide la primera, continúa con el resto.
  defp anterior(_conexion, []), do: nil

  defp anterior(conexion, [primera | resto]) do
    mismo_par =
      (conexion.origen == primera.origen and conexion.destino == primera.destino) or
        (conexion.origen == primera.destino and conexion.destino == primera.origen)

    if mismo_par, do: primera, else: anterior(conexion, resto)
  end

  # construir_grafo/1: recibe conexiones y devuelve los vecinos de cada ciudad.
  defp construir_grafo(conexiones) do
    Enum.reduce(conexiones, %{}, fn conexion, grafo ->
      grafo =
        Map.update(grafo, conexion.origen, [{conexion.destino, conexion.distancia}], fn vecinos ->
          vecinos ++ [{conexion.destino, conexion.distancia}]
        end)

      Map.update(grafo, conexion.destino, [{conexion.origen, conexion.distancia}], fn vecinos ->
        vecinos ++ [{conexion.origen, conexion.distancia}]
      end)
    end)
  end

  # resolver_consulta/4: revisa una consulta y escribe alcance y rutas;
  # devuelve :ok, incluso cuando la consulta es inválida.
  defp resolver_consulta(campos, linea, numero, grafo) do
    case campos do
      [origen, destino] ->
        origen = String.trim(origen)
        destino = String.trim(destino)
        titulo = "=== #{origen} -> #{destino} ==="
        mostrar(titulo)

        cond do
          Map.get(grafo, origen) == nil or Map.get(grafo, destino) == nil ->
            escribir(@alcance, "=== Alcance desde #{origen} ===")
            escribir(@alcance, "No se calcula: ciudad inexistente en el grafo")
            escribir(@alcance, "")
            mostrar("Ciudad inexistente en el grafo")
            mostrar("Número de rutas: 0")
            mostrar("")

          true ->
            pasos = alcance(origen, grafo)
            escribir(@alcance, "=== Alcance desde #{origen} ===")

            pasos
            |> Enum.with_index()
            |> Enum.each(fn {{ciudades, _}, paso} ->
              escribir(@alcance, "Paso #{paso}: #{Enum.join(ciudades, ", ")}")
            end)

            escribir(@alcance, "Se estabiliza en el paso #{length(pasos) - 1}")
            escribir(@alcance, "")
            {final, _} = ultimo(pasos)

            if Enum.any?(final, fn ciudad -> ciudad == destino end) do
              rutas = buscar(origen, destino, [origen], 0, grafo)
              informar_rutas(rutas)
            else
              mostrar("Sin rutas")
              mostrar("Número de rutas: 0")
            end

            mostrar("")
        end

      _ ->
        mostrar("Línea #{numero} de consultas: formato inválido -> #{linea}")
    end

    :ok
  end

  # alcance/2: recibe origen y grafo; devuelve los pasos hasta estabilizarse.
  # Un Stream infinito produce conjuntos hasta que el primero se repite.
  defp alcance(origen, grafo) do
    Stream.iterate({[origen], false}, fn {ciudades, _} ->
      siguientes = expandir(ciudades, grafo)
      {siguientes, siguientes == ciudades}
    end)
    |> Stream.take_while(fn {_, repetido} -> not repetido end)
    |> Enum.to_list()
  end

  # expandir/2: añade vecinos al conjunto recibido y lo devuelve sin repetidos.
  defp expandir(ciudades, grafo) do
    Enum.reduce(ciudades, ciudades, fn ciudad, todas ->
      vecinos = Map.get(grafo, ciudad, [])
      todas ++ Enum.map(vecinos, fn {nombre, _} -> nombre end)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ultimo/1: recibe una lista no vacía de pasos y devuelve el último.
  # Con [paso] termina; con más elementos se llama con el resto.
  defp ultimo([paso]), do: paso
  defp ultimo([_ | resto]), do: ultimo(resto)

  # buscar/5: recibe ciudad actual, destino, visitadas, distancia y grafo;
  # devuelve las rutas encontradas. Al llegar al destino crea una Ruta.
  # En otro caso avanza a vecinos no visitados y termina al agotar las ramas.
  defp buscar(destino, destino, visitadas, distancia, _grafo) do
    [%Ruta{ciudades: visitadas, distancia: distancia}]
  end

  defp buscar(actual, destino, visitadas, distancia, grafo) do
    Enum.reduce(Map.get(grafo, actual, []), [], fn {vecino, km}, rutas ->
      if Enum.any?(visitadas, fn ciudad -> ciudad == vecino end) do
        rutas
      else
        rutas ++ buscar(vecino, destino, visitadas ++ [vecino], distancia + km, grafo)
      end
    end)
  end

  # informar_rutas/1: recibe las rutas y escribe su detalle y los mínimos.
  defp informar_rutas([]), do: mostrar("Sin rutas")

  defp informar_rutas(rutas) do
    rutas
    |> Enum.with_index(1)
    |> Enum.each(fn {ruta, numero} ->
      mostrar(
        "Ruta #{numero}: #{Enum.join(ruta.ciudades, " -> ")} (#{length(ruta.ciudades)} ciudades, #{ruta.distancia} km)"
      )
    end)

    mostrar("Número de rutas: #{length(rutas)}")
    [corta | _] = Enum.sort_by(rutas, fn ruta -> length(ruta.ciudades) end)

    rutas_cortas =
      Enum.filter(rutas, fn ruta -> length(ruta.ciudades) == length(corta.ciudades) end)

    Enum.each(rutas_cortas, fn ruta ->
      mostrar("Ruta más corta: #{Enum.join(ruta.ciudades, " -> ")}")
    end)

    [menor | _] = Enum.sort_by(rutas, fn ruta -> ruta.distancia end)

    mostrar(
      "Ruta de menor distancia: #{Enum.join(menor.ciudades, " -> ")} (#{menor.distancia} km)"
    )
  end

  # mostrar/1: imprime una línea y la agrega al archivo de resultados.
  defp mostrar(linea) do
    IO.puts(linea)
    escribir(@salida, linea)
  end

  # limpiar/1: quita espacios y la marca BOM que agregan algunos editores.
  defp limpiar(linea), do: linea |> String.replace("\uFEFF", "") |> String.trim()

  # escribir/2: añade una línea con salto al archivo indicado.
  defp escribir(archivo, linea), do: File.write(archivo, linea <> "\n", [:append])
end

Ciudades.main()
