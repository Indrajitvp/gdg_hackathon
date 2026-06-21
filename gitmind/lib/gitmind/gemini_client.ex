defmodule Gitmind.GeminiClient do
  require Logger

  @api_url "https://genergenerativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

  @doc """
  Slices the given text into an array of atomic facts.
  """
  def slice_text(text) do
    api_key = Application.get_env(:gitmind, :gemini_api_key) || System.get_env("GEMINI_API_KEY")
    
    if is_nil(api_key) or api_key == "" do
      Logger.error("GEMINI_API_KEY is not set.")
      {:error, :missing_api_key}
    else
      prompt = """
      You are an expert learning assistant. Your task is to analyze the following input text and extract all core learning facts from it.
      
      Rules:
      1. Slice the text into small, self-contained "Atomic Facts".
      2. Each fact must be easy to read and understand on its own (under 15 words if possible).
      3. Do not include introductory text, explanations, or questions. Just return the raw statements.
      4. Output MUST be a JSON array of strings.
      
      Input text:
      \"\"\"
      #{text}
      \"\"\"
      """

      body = %{
        "contents" => [%{
          "parts" => [%{
            "text" => prompt
          }]
        }],
        "generationConfig" => %{
          "responseMimeType" => "application/json",
          "responseSchema" => %{
            "type" => "ARRAY",
            "description" => "List of atomic facts extracted from the input text",
            "items" => %{
              "type" => "STRING"
            }
          }
        }
      }

      # Gemini endpoint requires generative API key query param
      url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=#{api_key}"

      case Req.post(url, json: body) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          case parse_gemini_response(response_body) do
            {:ok, facts} when is_list(facts) -> {:ok, facts}
            _ -> {:error, :invalid_response_format}
          end
        {:ok, %Req.Response{status: status, body: error_body}} ->
          Logger.error("Gemini API error. Status: #{status}, Body: #{inspect(error_body)}")
          {:error, {:api_error, status}}
        {:error, exception} ->
          Logger.error("Gemini connection error: #{inspect(exception)}")
          {:error, :connection_failed}
      end
    end
  end

  defp parse_gemini_response(body) do
    # Gemini API response structure:
    # %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "[...json...]"}]}}]}
    with %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text_content}]}} | _]} <- body,
         {:ok, decoded} <- Jason.decode(text_content) do
      {:ok, decoded}
    else
      _error -> {:error, :parse_failed}
    end
  end
end
