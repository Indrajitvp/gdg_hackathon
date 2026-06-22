defmodule Gitmind.GeminiClient do
  require Logger

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
      1. Extract ONLY high-value, testable concepts.
      2. Formulate each concept as a Q&A flashcard with a 'front' (the question/prompt) and a 'back' (the concise answer).
      3. IGNORE single words, lists of names without context, or conversational filler. 
      4. If the input is just a list of random technologies (e.g., "Next.js", "Django"), DO NOT create facts for them unless there is descriptive context.
      5. Output MUST be a JSON array of objects with 'front' and 'back' fields. Return an empty array [] if no meaningful facts exist.
      
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
            "description" => "List of flashcards extracted from the input text",
            "items" => %{
              "type" => "OBJECT",
              "properties" => %{
                "front" => %{
                  "type" => "STRING",
                  "description" => "The question or prompt for the flashcard."
                },
                "back" => %{
                  "type" => "STRING",
                  "description" => "The concise answer to the question."
                }
              },
              "required" => ["front", "back"]
            }
          }
        }
      }

      # Gemini endpoint requires generative API key query param
      url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=#{api_key}"

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
