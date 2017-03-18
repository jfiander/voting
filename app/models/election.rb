class Election < ApplicationRecord
  has_many :votes

  validates :description, uniqueness: true

  before_save do
    self.description = "Test Election #{SecureRandom.hex(12)}" if self.description.blank?
    self.date = Time.now + 2.months if self.date.blank?
  end

  def self.new_test_election(iter = 100000)
    Election.transaction do
      Election.create(description: "Test Election #{SecureRandom.hex(12)}", date: Time.now + 2.months).random_gen(iter)
    end
  end

  def rank(batches: true, test: false, batch_size: 100000, participants: [])
    start_time = Time.now
    logger.info { "→ #{Election.time_since(start_time)}: Initializing..." }
    logger.info { "→ #{Election.time_since(start_time)}:   Loading light data..." }

    candidates        = Candidate.joins(:party).select("candidates.id, candidates.name, parties.name AS party")
    candidates        = participants.present? ? candidates.where(id: participants) : candidates.all
    candidates        = candidates.map(&:attributes).map(&:symbolize_keys!)
    viable_candidates = candidates.pluck(:id)
    candidate_count   = viable_candidates.count
    winner            = nil
    round             = 1
    rounds            = {}
    batches           = false if test

    in_batches  = batches ? " in batches" : ""
    logger.info { "→ #{Election.time_since(start_time)}:   Loading and mapping votes#{in_batches} for #{self.description}..." }
    if batches
      total_votes = self.votes.count
      num_batches = (total_votes.to_f / batch_size).ceil
      logger.info { "→ #{Election.time_since(start_time)}:   Total votes: #{total_votes} (#{num_batches} #{'batch'.pluralize(num_batches)})" }
      vote_preferences = {}
      self.votes.find_in_batches(batch_size: batch_size).map.with_index do |group, index|
        vote_preferences[index] = group.map do |vote|
          vote.preferences
        end

        batch_size = total_votes % batch_size if (total_votes.to_f / batch_size).ceil == index+1
        logger.info { "→ #{Election.time_since(start_time)}:     Mapped batch #{index+1} of #{num_batches} (#{batch_size} votes)..." }
      end

      vote_preferences = vote_preferences.values.flatten
    else
       votes = if test
        if test.is_a? Integer
          logger.info { "→ #{Election.time_since(start_time)}:     Selecting first #{test} votes..." }
          self.votes.limit(test)
        elsif test.is_a? Array
          bottom = test[0]-1 > 0 ? test[0]-1 : 0
          top    = test[1] > bottom ? test[1] : 10000
          logger.info { "→ #{Election.time_since(start_time)}:     Selecting votes #{bottom+1} thru #{top}..." }
          self.votes.offset(bottom).limit(top-bottom-1)
        else
          logger.info { "→ #{Election.time_since(start_time)}:     Selecting first 10000 votes..." }
          self.votes.limit(10000)
        end
      else
        logger.info { "→ #{Election.time_since(start_time)}:     Selecting all votes in one batch..." }
        self.votes
      end

      logger.info { "→ #{Election.time_since(start_time)}:     Mapping all votes to preferences..." }
      vote_preferences = votes.map(&:preferences)
    end

    total_votes = vote_preferences.count

    logger.info { "→ #{Election.time_since(start_time)}: Initialization complete. Calculating preferences..." }
    while winner.nil?
      logger.info { "→ #{Election.time_since(start_time)}: #{TermStyle.bold.underline}Round \##{round}#{TermStyle.reset}" }
      rounds[round] = {}

      # Initialize empty counts for remaining viable candidates
      viable_candidates.each do |viable|
        rounds[round][viable] = 0
      end
      logger.info { "→ #{Election.time_since(start_time)}:   Viable candidates for round \##{round}: #{TermStyle.bold}#{viable_candidates.count}#{TermStyle.reset}" }

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
      logger.info { "→ #{Election.time_since(start_time)}:   Total votes for round \##{round}: #{TermStyle.bold}#{round_total}#{TermStyle.reset} (#{(100*round_total.to_f / total_votes).round(2)}\% of all votes)" }

      # Skip if there is a winner
      unless winner? rounds[round]
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
                "→ #{Election.time_since(start_time)}:   #{TermStyle.red.bright}Rejected#{TermStyle.reset}: #{TermStyle.bold}#{candidate[:name]}#{TermStyle.reset} (\##{candidate[:id]}, #{candidate[:party]}, #{votes} votes)"
              end
            end
          else
            # Tie involves leader; winner is determined by highest number of first preference votes; else second; else third; etc. 
            # In case of true tie, winner is determined randomly
            tie     = rounds[round].keys
            logger.info { "→ #{Election.time_since(start_time)}:   * #{TermStyle.yellow.bright}Leading tie detected#{TermStyle.reset}" }
            logger.info do
              tie_str = tie.map { |id| candidates.select { |c| c[:id] == id }.first }.map { |c| "\##{c[:id]}: #{c[:name]} (#{c[:party]})" }.join(", ")
              "              * Tied candidates: #{tie_str}"
            end
            logger.info { "              * Votes: #{rounds[round].first.last}" }
            
            tied = true
            pref = 1
            while tied
              votes_for_pref = vote_preferences.map { |v| v[pref] }.group_by { |n| n }.map { |c,v| {c => v.count} }.reduce({}, :merge)
              votes_for_pref = {0=>0} if votes_for_pref.keys.reject { |k| k.nil?}.empty?
              max_votes_for_pref = votes_for_pref.max_by { |k,v| v }.last
              logger.info { "→ #{Election.time_since(start_time)}:   * Highest #{pref}#{pref.ordinal} preference votes: #{max_votes_for_pref}" }

              if votes_for_pref.select { |k,v| v == max_votes_for_pref }.count == 1
                winner = candidates.select { |c| c[:id] == votes_for_pref.select { |k,v| v == max_votes_for_pref }.first.first }.first
                if winner.present?
                  logger.info do
                    "→ #{Election.time_since(start_time)}:   * #{TermStyle.green.bright}Elected#{TermStyle.reset}: #{TermStyle.bold}#{winner[:name]}#{TermStyle.reset} (\##{winner[:id]}, #{winner[:party]}) has won the tie by #{pref}#{pref.ordinal} preference votes."
                  end
                end
                break
              else
                pref += 1
              end
            end

            unless winner.present?
              # True tie; decide winner randomly from tied candidates
              winner = candidates.select { |c| c[:id] == tie[Random.rand(0..tie.count-1)] }.first
              if winner.present?
                logger.info do
                  "→ #{Election.time_since(start_time)}:   * #{TermStyle.green.bright}Elected#{TermStyle.reset}: #{TermStyle.bold}#{winner[:name]}#{TermStyle.reset} (\##{winner[:id]}, #{winner[:party]}) has been randomly selected."
                end
              end
              break
            end
          end
        else
          # No tie detected
          viable_candidates = (viable_candidates - [lowest.first])
          logger.info do
            candidate = candidates.select { |c| c[:id] == lowest.first }.first
            "→ #{Election.time_since(start_time)}:   #{TermStyle.red.bright}Rejected#{TermStyle.reset}: #{TermStyle.bold}#{candidate[:name]}#{TermStyle.reset} (\##{candidate[:id]}, #{candidate[:party]}, #{lowest.last} votes)"
          end
        end
      end

      # Determine if one candidate has a majority of votes for viable candidates
      rounds[round].each do |candidate, vote_count|
        if vote_count >= ( (round_total.to_f / 2).floor + 1 ) || viable_candidates.count == 1
          winner = if viable_candidates.count == 1
            candidates.select { |c| c[:id] == viable_candidates.first }.first
          else
            candidates.select { |c| c[:id] == candidate }.first
          end
          logger.info do
            first_round = (100*rounds[1][winner[:id]].to_f/rounds[1].values.sum).round(2)
            final_round = (100*rounds[round].values.max.to_f/round_total).round(2)

            percents_note = if round > 1
              "#{final_round}\% of round #{round} votes and #{first_round}\% of first preference votes"
            else
              "#{first_round}\% of first preference votes"
            end

            "→ #{Election.time_since(start_time)}:   #{TermStyle.green.bright}Elected#{TermStyle.reset}: #{TermStyle.bold}#{winner[:name]}#{TermStyle.reset} (\##{winner[:id]}, #{winner[:party]}, #{rounds[round].values.max} votes, #{percents_note})"
          end
          break
        end
      end

      unless winner.present?
        logger.info do
          leader = candidates.select { |c| c[:id] == rounds[round].max_by { |_,v| v }.first }.first
          current_votes = (100*rounds[round].values.max.to_f/round_total).round(2)
          "→ #{Election.time_since(start_time)}:   #{TermStyle.yellow.bright}Leading#{TermStyle.reset}: #{TermStyle.bold}#{leader[:name]}#{TermStyle.reset} (\##{leader[:id]}, #{leader[:party]}), with #{current_votes}\% of round #{round} votes."
        end
      end

      logger.info { "→ #{Election.time_since(start_time)}:   Completed round \##{round}." }
      # Increment round
      round += 1
    end

    logger.info { "→ #{Election.time_since(start_time)}: Cleaning up output..." }
    # Map rounds keys to candidates
    rounds = rounds.map do |round, counts|
      counts = counts.map do |candidate_id, vote_count|
        {candidates.select { |c| c[:id] == candidate_id }.first => vote_count}
      end

      {
        round => counts.reduce({}, :merge)
      }
    end

    logger.info { "→ Took #{Election.time_since(start_time)}" }

    {
      winner: winner,
      rounds: rounds.reduce({}, :merge)
    }
  end

  def random_gen(iter = 10, bias: nil, weights: [], weight_type: :inclusion)
    if iter > 1000000
      iter = 1000000
      logger.warn { "Warning: A maximum of 1,000,000 ballots can be generated at a time." }
      logger.warn { "         To generate more than that, please use #{TermStyle.bold}Vote.multi_random_gen#{TermStyle.reset}." }
      sleep 2
    end

    # Generate some random votes
    start_time       = Time.now
    logger.info { "→ #{Election.time_since(start_time)}: Initializing..." }

    initial_count    = self.votes.count
    candidates_count = Candidate.count
    valid_candidates = Candidate.all.map(&:id)

    votes = []

    bias_description = ""
    weights_for_desc = weights.reject { |_,w| w.nil? || w == 0 }
    if weights.present? && weight_type == :inclusion
      cumulative_weights = {}
      weights_total = 0
      weights.each do |c, w|
        weights_total += w
        cumulative_weights[c] = weights_total
      end
      bias_description = ", weighted as #{weights_for_desc}"
    elsif weights.present? && weight_type == :exclusion
      weights_total = weights.values.sum
      Candidate.all.each do |c|
        weights[c.id] = 0 unless weights.has_key?(c.id)
      end
      bias_description = ", weighted as #{weights_for_desc}"
    elsif bias.present?
      bias_description = ", biased with candidate #{bias[1]} at preference #{bias[0]}"
    end

    logger.info { "→ #{Election.time_since(start_time)}: Generating #{iter} random ballots#{bias_description} for #{self.description}..." }
    iter.times do |i|
      candidate_ids = valid_candidates
      preferences = Random.rand(1..candidate_ids.count)
      vote_hash = if weights.present? && weight_type == :inclusion
        selections = {}
        this_vote = {}
        candidates_to_choose = []
        preferences.times do
          selection = Random.rand(weights_total)
          candidates_to_choose << cumulative_weights.reject { |c, w| w < selection }.first.first
        end

        preferences.times do |index|
          selection = Random.rand(weights_total)
          selections[index] = cumulative_weights.reject { |c, w| w < selection }.first.first
        end

        selections
      elsif weights.present? && weight_type == :exclusion
        Hash[(1..preferences).to_a.zip(candidate_ids.shuffle.first(preferences-1))].reject! { |_, c| c.nil? || (weights[c] < Random.rand(weights_total)+1) }
      elsif bias.present?
        candidate_ids = candidate_ids - [bias[:candidate]]
        Hash[(1..preferences).to_a.zip(candidate_ids.shuffle.first(preferences-1).insert(bias[:preference]-1, bias[:candidate]))]
      else
        Hash[(1..preferences).to_a.zip(candidate_ids.shuffle.first(preferences))]
      end

      votes << vote_hash
    end

    logger.info { "→ #{Election.time_since(start_time)}: Storing ballots in database..." }
    Election.disable_logs_while do
      Vote.bulk_insert(:preferences_hash, :election_id, :created_at, :updated_at) do |w|
        votes.each do |v|
          w.add [Vote.format_preferences(v), self.id]
        end
      end
    end

    self
  ensure
    new_votes = self.votes.count - initial_count
    logger.info { "→ Generated #{new_votes} new ballots#{bias_description}" }
    logger.info { "→ Took #{Election.time_since(start_time)}" }
  end

  def multi_random_gen(iter = 10, cap: 100000, bias: [], weights: {}, weight_type: nil)
    start_time = Time.now
    iter.times do |i|
      logger.info { "→ #{Election.time_since(start_time)}: Beginning random_gen cycle \##{i+1}..." }
      self.random_gen(cap, bias: bias, weights: weights, weight_type: weight_type)
    end
    logger.info { "→ Took #{Election.time_since(start_time)}" }

    self
  end
  
  def self.demo(save: false, weighted: true)
    begin
      Election.transaction do
        parties = Party.create([
          {name: "Party A"},
          {name: "Party B"},
          {name: "Party C"}
        ])
        candidates = Candidate.create([
          {name: "Candidate 1", party: Party.find_by(name: "Party A")},
          {name: "Candidate 2", party: Party.find_by(name: "Party A")},
          {name: "Candidate 3", party: Party.find_by(name: "Party B")},
          {name: "Candidate 4", party: Party.find_by(name: "Party C")},
          {name: "Candidate 5", party: Party.find_by(name: "Party C")},
        ])
        election = Election.create
        if weighted
          election.random_gen(25000, weights: candidates.map { |c| {c.id => 2*Random.rand(candidates.count)+1} }.reduce({}, :merge))
        else
          election.random_gen(25000)
        end
        @demo_results = election.rank(participants: candidates.map(&:id))
        raise unless save
      end
    rescue
      # Do nothing
    end
    puts "Demo complete!"
    @demo_results
  end


  private
  def self.time_since(start_time)
    Time.at(Time.now - start_time).utc.strftime("%H:%M:%S")
  end

  def self.disable_logs_while(&block)
    old_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = nil
    yield
  ensure
    ActiveRecord::Base.logger = old_logger
  end

  def winner?(round_data)
    round_total = round_data.values.sum
    round_data.map { |_, v| v.to_f > ((round_total.to_f / 2) + 1) }.any?
  end
end
