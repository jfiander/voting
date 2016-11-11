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
    iter.times do
      # Generate some random votes

      candidates_count = Candidate.count
      # Determine number of votes to cast
      preferences = Random.rand(1..candidates_count)

      # Determine candidates voted for
      candidates = []
      preferences.times do |pref|
        candidate = Candidate.find_by(id: Random.rand(1..candidates_count)) while candidates.include?(candidate) || candidate.blank?
        candidates << candidate
      end

      # Build preferences hash
      vote_hash = Hash[(1..preferences).map(&:to_s).zip(candidates.map(&:id).map(&:to_s))]

      Vote.create(preferences_hash: vote_hash)
    end
  end

  def self.rank
    votes = Vote.all
    vote_preferences = votes.map(&:preferences)
    rounds = {}

    viable_candidates = Candidate.all.map(&:id)
    candidate_count   = viable_candidates.count

    winner = nil
    round  = 1
    while winner.nil?
      if round == 1
        prefs = vote_preferences.map do |vote|
          vote[round]
        end
        rounds[round] = prefs.each_with_object(Hash.new(0)) { |h1, h2| h2[h1] += 1 }
      else
        rounds[round] = {}

        # Initialize empty counts for remaining viable candidates
        viable_candidates.each do |viable|
          rounds[round][viable] = 0
        end

        # Increment rounds[round][viable] for each vote that now has viable as its highest-ranked viable_candidate
        vote_preferences.each do |vote|
          (1..vote.count).each do |rank|
            if viable_candidates.include?(vote[rank])
              rounds[round][vote[rank]] += 1
              break
            end
          end
        end
      end

      # Count the total number of votes for viable candidates in this round
      round_total = rounds[round].values.sum

      # Determine if one candidate has a majority of votes for viable candidates
      rounds[round].each do |candidate, vote_count|
        winner = candidate if vote_count > ( (round_total.to_f / 2) + 1 )
      end

      # Remove lowest scoring candidate from the viable candidates pool
      lowest = rounds[round].min_by { |candidate, vote_count| vote_count }
      viable_candidates = (viable_candidates - [lowest.first])

      # Increment round
      round += 1
    end

    # Map rounds keys to candidates
    rounds = rounds.map do |round, counts|
      counts = counts.map do |candidate_id, vote_count|
        {Candidate.find_by(id: candidate_id) => vote_count}
      end

      {
        round => counts.reduce({}, :merge)
      }
    end

    winner_hash = Candidate.find_by(id: winner).slice(:id, :name, :party_id).symbolize_keys.map do |key, value|
      if key == :party_id
        {party: Party.get(value).name}
      else
        {key => value}
      end
    end

    {
      winner: winner_hash.reduce({}, :merge),
      rounds: rounds.reduce({}, :merge)
    }
  end
end
