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
    initial_count    = Vote.count
    candidates_count = Candidate.count

    iter.times do
      # Determine number of votes to cast
      preferences = Random.rand(1..candidates_count)

      # Determine candidates voted for
      candidates = []
      preferences.times do |pref|
        candidate = Random.rand(1..candidates_count) while candidates.include?(candidate) || candidate.blank?
        candidates << candidate
      end

      # Build preferences hash
      vote_hash = Hash[(1..preferences).map(&:to_s).zip(candidates.map(&:to_s))]

      Vote.create(preferences_hash: vote_hash)
    end
  ensure
    logger.info { "Generated #{Vote.count - initial_count} new votes" }
    logger.info { "Took #{time_since(start_time)}" }
  end

  def self.rank
    start_time = Time.now
    logger.info { "→ #{time_since(start_time)}: Initializing..." }

    votes             = Vote.all
    parties           = Party.all
    candidates        = Candidate.all
    viable_candidates = candidates.map(&:id)
    candidate_count   = viable_candidates.count
    winner            = nil
    round             = 1
    rounds            = {}

    logger.info { "→ #{time_since(start_time)}: Mapping votes..." }
    vote_preferences = votes.map(&:preferences)

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

      # Determine if one candidate has a majority of votes for viable candidates
      rounds[round].each do |candidate, vote_count|
        if vote_count > ( (round_total.to_f / 2) + 1 )
          winner = candidate
          logger.info { "→ #{time_since(start_time)}:   Candidate \##{winner} (#{candidates.select { |c| c.id == winner }.first.name}) has been elected." }
        end
      end

      # Remove lowest scoring candidate from the viable candidates pool
      lowest = rounds[round].min_by { |candidate, vote_count| vote_count }
      viable_candidates = (viable_candidates - [lowest.first])
      logger.info { "→ #{time_since(start_time)}:   Candidate \##{lowest} (#{candidates.select { |c| c.id == lowest.first }.first.name}) has been rejected." }

      logger.info { "→ #{time_since(start_time)}:   Completed round \##{round}." }
      # Increment round
      round += 1
    end

    logger.info { "→ #{time_since(start_time)}: Cleaning up output..." }
    # Map rounds keys to candidates
    rounds = rounds.map do |round, counts|
      counts = counts.map do |candidate_id, vote_count|
        {candidates.select { |c| c.id == candidate_id }.first.slice(:name, :party_id).symbolize_keys.map { |k,v| k == :party_id ? {party: parties.select { |p| p.id == v }.first.name} : {k => v} }.reduce({}, :merge) => vote_count}
      end

      {
        round => counts.reduce({}, :merge)
      }
    end

    winner_hash = candidates.select {|c| c.id == winner }.first.slice(:id, :name, :party_id).symbolize_keys.map do |key, value|
      if key == :party_id
        {party: parties.select { |p| p.id == value }.first.name}
      else
        {key => value}
      end
    end

    logger.info { "Took #{time_since(start_time)}" }

    {
      winner: winner_hash.reduce({}, :merge),
      rounds: rounds.reduce({}, :merge)
    }
  end

  private
  def self.time_since(start_time)
    Time.at(Time.now - start_time).utc.strftime("%H:%M:%S")
  end
end
