class User < ActiveRecord::Base
  has_many :proposals, :foreign_key => :proposer_id
  has_many :suggestions, :foreign_key => :author_id
  has_many :proposals_of_interest, :through => :suggestions, :source => :proposal, :uniq => true

  acts_as_voter
  has_karma(:proposals, :as => :proposer)

  scope :with_signup_reasons, where("signup_reason IS NOT NULL")
  scope :without_signup_reasons, where(:signup_reason => nil)
  scope :by_contribution, order("contribution_score DESC")

  attr_accessible :signup_reason,
                  :subscribe_to_suggestions_notifications

  before_save :update_contribution_score

  def proposals_you_should_look_at
    Proposal.active.without_suggestions_from(self).without_votes_from(self).not_proposed_by(self)
  end

  def proposals_without_own_votes
    Proposal.active.without_votes_from(self).not_proposed_by(self)
  end

  def proposals_that_have_changed
    proposals_of_interest.active.not_proposed_by(self).includes(:suggestions).select { |p| p.updated_at > p.suggestions.by(self).maximum(:updated_at) }
  end

  def proposals_that_have_been_withdrawn
    proposals_of_interest.withdrawn
  end

  def self.create_with_omniauth(auth)
    auth = auth.with_indifferent_access

    create! do |user|
      user.name = auth[:info][:name] || auth[:info][:nickname]
      user.send(:"#{auth[:provider]}_uid=", auth[:uid])
      user.send(:"#{auth[:provider]}_nickname=", auth[:info][:nickname])
      user.email = auth[:info][:email]
    end
  end

  def self.find_or_create_with_omniauth(auth)
    auth = auth.with_indifferent_access

    self.where("#{auth[:provider]}_uid = ? OR email =?",
               auth[:uid],
               auth[:info][:email]).first ||
        self.create_with_omniauth(auth)
  end

  def update_provider_details(auth)
    auth = auth.with_indifferent_access

    self.send(:"#{auth[:provider]}_uid=", auth[:uid]) if self.send(:"#{auth[:provider]}_uid").blank?
    self.send(:"#{auth[:provider]}_nickname=", auth[:info][:nickname]) if self.send(:"#{auth[:provider]}_nickname").blank?
    self.save
  end

  def  update_last_visit
    self.last_visited_at = DateTime.now
    self.save!
  end

  REASON_WEIGHT = 5
  SUGGESTION_WEIGHT = 2

  def proposals_with_interest
    proposals.select { |p| p.suggestions.any? }
  end

  def update_contribution_score
    self.contribution_score = (suggestions.not_on_proposals_by(self).count * SUGGESTION_WEIGHT)
    self.contribution_score += REASON_WEIGHT if self.signup_reason.present?
  end

  ### ACL Stuff ###

  def moderator?
    self.committee_member?
  end

  def committee_member?
    self.email.present? && self.email =~ /@euruko2013\.org$/
  end
end
