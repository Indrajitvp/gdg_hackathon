defmodule Gitmind.ReviewEngine do
  @moduledoc """
  Implements the SuperMemo-2 (SM-2) algorithm for spaced repetition.
  """

  @doc """
  Calculates the next spaced repetition metrics.
  
  Parameters:
    - feedback: :forgot, :hard, or :easy
    - interval: current interval in days
    - ease_factor: current ease factor (float)
    - repetitions: current repetitions count (integer)
    
  Returns a map containing:
    - :interval (new interval in days)
    - :ease_factor (new ease factor)
    - :repetitions (new repetitions count)
    - :next_review_at (DateTime of the next review)
  """
  def calculate(feedback, interval, ease_factor, repetitions) do
    # Map feedback to quality scores (0-5 scale)
    quality =
      case feedback do
        :forgot -> 1
        :hard -> 3
        :easy -> 5
      end

    {new_reps, new_interval} =
      if quality < 3 do
        {0, 1}
      else
        case repetitions do
          0 -> {1, 1}
          1 -> {2, 6}
          _ -> {repetitions + 1, round(interval * ease_factor)}
        end
      end

    # Calculate new ease factor
    # EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
    diff = 5 - quality
    new_ease = ease_factor + (0.1 - diff * (0.08 + diff * 0.02))
    
    # Clamp ease factor to a minimum of 1.3
    new_ease = max(new_ease, 1.3)

    # Next review date (current UTC time + interval in days)
    next_review_at = 
      DateTime.utc_now()
      |> DateTime.add(new_interval, :day)
      |> DateTime.truncate(:second)

    %{
      interval: new_interval,
      ease_factor: Float.round(new_ease, 2),
      repetitions: new_reps,
      next_review_at: next_review_at
    }
  end
end
