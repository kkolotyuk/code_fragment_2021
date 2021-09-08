class Ticket < ApplicationRecord
  include RandomId

  OPEN_STATUS = 'open'
  CLOSED_STATUS = 'closed'
  TICKET_STATUSES = [OPEN_STATUS, CLOSED_STATUS]

  PREFERRED_CONTACT_EMAIL = 'email'
  PREFERRED_CONTACT_PHONE = 'phone'
  PREFERRED_CONTACTS = [PREFERRED_CONTACT_EMAIL, PREFERRED_CONTACT_PHONE]

  belongs_to :user, inverse_of: :tickets
  belongs_to :author_admin, class_name: 'Admin', inverse_of: :own_tickets,  optional: true
  belongs_to :author_user, class_name: 'User', inverse_of: :own_tickets,  optional: true
  belongs_to :order, inverse_of: :tickets, touch: true, optional: true
  belongs_to :ordered_assay, inverse_of: :tickets, touch: true, optional: true
  has_many :comments, -> { order 'updated_at' }, inverse_of: :ticket, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 10000 }
  validates :user, presence: true # user ticket connected with (DB denormalization)
  validates :status, inclusion: { in: TICKET_STATUSES, message: "is invalid" }, presence: true
  validate :order_xor_ordered_assay
  validates :preferred_contact, inclusion: { in: PREFERRED_CONTACTS, message: "is invalid" }, allow_nil: true
  validate :preferred_contact_phone

  before_save :set_random_id

  def self.search(status, ordered_assay_id, order_id)
    query = all
    if status.present?
      query = query.where(status: status)
    end
    if ordered_assay_id.present?
      query = query.where(ordered_assay_id: ordered_assay_id)
    end
    if order_id.present?
      query = query.where(order_id: order_id)
    end
    query
  end

  def closed?
    status == CLOSED_STATUS
  end

  def open?
    status == OPEN_STATUS
  end

  def author(hide_admin = true)
    if author_user_id.present?
      author_user
    elsif author_admin_id.present? && !hide_admin
      author_admin
    else
      # Some tickets are created by the system. They don't have author.
      OpenStruct.new(full_name: 'Bioproximity Support')
    end
  end

  private

  def order_xor_ordered_assay
    unless !!order_id ^ !!ordered_assay_id
      errors.add(:order_id, "Specify an order or a project, not both")
      errors.add(:ordered_assay_id, "Specify an order or a project, not both")
    end
  end

  def preferred_contact_phone
    if preferred_contact == PREFERRED_CONTACT_PHONE && !user.has_phone?
      errors.add(:preferred_contact, "Specify phone number on profile page")
    end
  end

  def set_random_id
    self.id = random_id if new_record?
  end
end
