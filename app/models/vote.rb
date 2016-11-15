class Vote < ApplicationRecord
  def preferences
    hash = JSON.parse(self.preferences_hash.gsub('=>', ':')).map do |preference, candidate_id|
      {preference.to_i => candidate_id.to_i}
    end

    hash.reduce({}, :merge)
  end

  def store_preferences(hash)
    preferences_hash = "{"
    preferences_hash += hash.map { |preference, candidate| "\"#{preference}\"=>\"#{candidate.id}\""}.join(",")
    preferences_hash += "}"

    self.update(preferences_hash: preferences_hash)
  end

  def self.random_gen(iter = 10)
    # Generate some random votes
    start_time       = Time.now
    logger.info { "→ #{time_since(start_time)}: Initializing..." }

    initial_count    = Vote.count
    candidates_count = Candidate.count

    logger.info { "→ #{time_since(start_time)}: Generating #{iter} random ballots..." }
    iter.times do |i|
      logger.info { "→ #{time_since(start_time)}:   Generating random ballot \##{i+1}..." }
      # Determine number of votes to cast
      preferences = Random.rand(1..candidates_count)
      logger.info { "→ #{time_since(start_time)}:     Selecting #{preferences} random votes..." }

      # Determine candidates voted for
      candidates = []
      preferences.times do |pref|
        candidate = Random.rand(1..candidates_count) while candidates.include?(candidate) || candidate.blank?
        logger.info { "→ #{time_since(start_time)}:       Vote for candidate \##{candidate}." }
        candidates << candidate
      end

      # Build preferences hash
      vote_hash = Hash[(1..preferences).map(&:to_s).zip(candidates.map(&:to_s))]

      Vote.create(preferences_hash: vote_hash)
      logger.info { "→ #{time_since(start_time)}:     Ballot \##{i+1} generated." }
    end
  ensure
    logger.info { "→ Generated #{Vote.count - initial_count} new votes" }
    logger.info { "→ Took #{time_since(start_time)}" }
  end

  def self.rank(batches: true, test: false)
    start_time = Time.now
    logger.info { "→ #{time_since(start_time)}: Initializing..." }
    logger.info { "→ #{time_since(start_time)}:   Loading light data..." }

    candidates        = Candidate.joins(:party).select("candidates.id, candidates.name, parties.name AS party").all.map(&:attributes).map(&:symbolize_keys!)
    viable_candidates = candidates.pluck(:id)
    candidate_count   = viable_candidates.count
    winner            = nil
    round             = 1
    rounds            = {}
    batches           = false if test

    in_batches = batches ? " in batches" : ""
    logger.info { "→ #{time_since(start_time)}:   Loading and mapping votes#{in_batches}..." }
    if batches
      batch_size = 100000
      vote_preferences = {}
      Vote.find_in_batches(batch_size: batch_size).map.with_index do |group, index|
        vote_preferences[index] = group.map do |vote|
          vote.preferences
        end

        logger.info { "→ #{time_since(start_time)}:     Mapped #{index+1} #{'batch'.pluralize(index+1)} of #{batch_size} votes..." }
      end

      vote_preferences = vote_preferences.values.flatten
    else
       votes = if test
        if test.is_a? Integer
          Vote.limit(test)
        else
          Vote.limit(10000)
        end
      else
        Vote.all
      end

      vote_preferences = votes.map(&:preferences)
    end

    logger.info { "→ #{time_since(start_time)}: Initialization complete. Calculating preferences..." }
    while winner.nil?
      logger.info { "→ #{time_since(start_time)}: Beginning round \##{round}..." }
      rounds[round] = {}

      # Initialize empty counts for remaining viable candidates
      viable_candidates.each do |viable|
        rounds[round][viable] = 0
      end
      logger.info { "→ #{time_since(start_time)}:   Viable candidates for round \##{round}: #{viable_candidates.count}..." }

      # Increment count for the candidate that has the highest-ranked viable preference of each vote
      vote_preferences.each do |vote|
        (1..vote.count).each do |rank|
          if viable_candidates.include?(vote[rank])
            rounds[round][vote[rank]] += 1
            break
          end
        end
      end

      # Count the total number of votes for viable candidates in this round
      round_total = rounds[round].values.sum
      logger.info { "→ #{time_since(start_time)}:   Total votes for round \##{round}: #{round_total}." }

      # Remove lowest scoring candidate from the viable candidates pool
      lowest = rounds[round].min_by { |candidate, vote_count| vote_count }

      # Detect any ties
      if rounds[round].values.select { |v| v == lowest.last }.count > 1
        # Check if there's at least one candidate above the tie; if not, enter tie breaker
        if rounds[round].values.select { |v| v > lowest.last }.count >= 1
          # Tie does not involve leader; redistribute all votes and proceed
          lowests = rounds[round].select { |_,v| v == lowest.last }
          lowests.each do |id, votes|
            viable_candidates = (viable_candidates - [id])
            logger.info do
              candidate = candidates.select { |c| c[:id] == id }.first
              "→ #{time_since(start_time)}:   Candidate \##{candidate[:id]} (#{candidate[:name]}, #{candidate[:party]}, #{votes} votes) has been rejected."
            end
          end
        else
          # Tie involves leader; winner is determined by highest number of first preference votes; else second; else third; etc. 
          # In case of true tie, winner is determined randomly
          tie     = rounds[round].keys
          logger.info { "→ #{time_since(start_time)}:   * Leading tie detected..." }
          logger.info do
            tie_str = tie.map { |id| candidates.select { |c| c[:id] == id }.first }.map { |c| "\##{c[:id]}: #{c[:name]} (#{c[:party]})" }.join(", ")
            "              * Tied candidates: #{tie_str}"
          end
          logger.info { "              * Votes: #{rounds[round].first.last}" }
          
          tied = true
          pref = 1
          while tied
            votes_for_pref = vote_preferences.map { |v| v[pref] }.group_by { |n| n }.map { |c,v| {c => v.count} }.reduce({}, :merge)
            max_votes_for_pref = votes_for_pref.max_by { |k,v| v }.last
            logger.info { "→ #{time_since(start_time)}:   * Highest #{pref}#{pref.ordinal} preference votes: #{max_votes_for_pref}" }

            if votes_for_pref.select { |k,v| v == max_votes_for_pref }.count == 1
              winner = candidates.select { |c| c[:id] == votes_for_pref.select { |k,v| v == max_votes_for_pref }.first.first }.first
              logger.info do
                "→ #{time_since(start_time)}:   * Candidate \##{winner[:id]} (#{winner[:name]}, #{winner[:party]}) has won the tie by #{pref}#{pref.ordinal} preference votes and has been elected."
              end
              break
            else
              pref += 1
            end
          end

          unless winner.present?
            # True tie; decide winner randomly from tied candidates
            winner = tie[Random.rand(0..tie.count-1)]
            logger.info do
              "→ #{time_since(start_time)}:   * Candidate \##{winner[:id]} (#{winner[:name]}, #{winner[:party]}) has been randomly selected and has been elected."
            end
          end
        end
      else
        # No tie detected
        viable_candidates = (viable_candidates - [lowest.first])
        logger.info do
          candidate = candidates.select { |c| c[:id] == lowest.first }.first
          "→ #{time_since(start_time)}:   Candidate \##{candidate[:id]} (#{candidate[:name]}, #{candidate[:party]}, #{lowest.last} votes) has been rejected."
        end
      end

      # Determine if one candidate has a majority of votes for viable candidates
      rounds[round].each do |candidate, vote_count|
        if vote_count >= ( (round_total.to_f / 2).floor + 1 ) || viable_candidates.count == 1
          if viable_candidates.count == 1
            winner = candidates.select { |c| c[:id] == viable_candidates.first }.first
            logger.info do
              "→ #{time_since(start_time)}:   Candidate \##{winner[:id]} (#{winner[:name]}, #{winner[:party]}, #{vote_count} votes) has been elected."
            end
            break
          else
            winner = candidates.select { |c| c[:id] == candidate }.first
            logger.info do
              "→ #{time_since(start_time)}:   Candidate \##{winner[:id]} (#{winner[:name]}, #{winner[:party]}, #{vote_count} votes) has been elected."
            end
            break
          end
        end
      end

      logger.info { "→ #{time_since(start_time)}:   Completed round \##{round}." }
      # Increment round
      round += 1
    end

    logger.info { "→ #{time_since(start_time)}: Cleaning up output..." }
    # Map rounds keys to candidates
    rounds = rounds.map do |round, counts|
      counts = counts.map do |candidate_id, vote_count|
        {candidates.select { |c| c[:id] == candidate_id }.first => vote_count}
      end

      {
        round => counts.reduce({}, :merge)
      }
    end

    logger.info { "→ Took #{time_since(start_time)}" }

    {
      winner: winner,
      rounds: rounds.reduce({}, :merge)
    }
  end

  private
  def self.time_since(start_time)
    Time.at(Time.now - start_time).utc.strftime("%H:%M:%S")
  end
end
