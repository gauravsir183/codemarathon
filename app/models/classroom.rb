class Classroom < ApplicationRecord
  belongs_to :course
  has_many :classroom_records, dependent: :destroy

  validates :name, presence: true
  validates :course, presence: true
  validates :slug, presence: true
  validates :slug, uniqueness: true
  validates :slug, length: { in: 5..20 }
  validates :slug, format: { with: /[a-z0-9\-]/,
    message: "only allows lower case letters, digits and dashes, "\
              "with length between 5 and 20 symbols" }

  def to_param
    slug
  end

  def add_admin user, active=true
    add_user(user, ClassroomRecord::ROLE_ADMIN, active)
  end

  def is_admin? user
    classroom_records.exists?(user: user, role: ClassroomRecord::ROLE_ADMIN,
      active: true)
  end

  def add_student user, active=true
    add_user(user, ClassroomRecord::ROLE_STUDENT, active)
  end

  def is_student? user
    classroom_records.exists?(user: user, role: ClassroomRecord::ROLE_STUDENT,
      active: true)
  end

  # Explicitly checking by user role to guard us against any future roles
  # that may be added.
  def has_access? user
    user.present? && (is_admin?(user) || is_student?(user))
  end

  def remove_user user
    classroom_records.where(user: user).delete_all
  end

  def find_lesson lesson_id
    lesson = Lesson.find(lesson_id)
    return if course.id != lesson.section.course_id

    lesson
  end

  def find_task task_id, lesson_id
    lesson = find_lesson lesson_id
    return unless lesson

    lesson.tasks.find(task_id)
  end

  def find_quiz quiz_id, lesson_id
    lesson = find_lesson lesson_id
    return unless lesson

    lesson.quizzes.find(quiz_id)
  end

  def spots_left
    return Float::INFINITY if user_limit.nil?

    [user_limit - classroom_records.active.count, 0].max
  end

  def is_waiting? user
    classroom_records.exists?(user: user, active: false)
  end

  def update_user_limit new_user_limit
    Classroom.transaction do
      update_attributes(user_limit: new_user_limit)

      new_spots = spots_left

      if new_spots > 0
        Rails.logger.info("#{ new_spots } new spots opened up in classroom #{ id }")
        if new_spots == Float::INFINITY
          records = classroom_records.inactive.order("created_at asc")
        else
          records = classroom_records.inactive.order("created_at asc").limit(new_spots)
        end

        Rails.logger.info("Giving access to #{ records.count } users in classroom #{ id }")
        records.update_all(active: true)
      end
    end
  end

  def activate_user user
    record = classroom_records.find_by(user: user)
    record.update_attributes(active: true) if record.present?
  end

  def first_lesson user
    if user.present?
      course.first_visible_lesson(user)
    elsif course.sections.present?
      course.sections.visible.ordered.first.lessons.visible.ordered.first
    end
  end

  private

  def add_user user, role, active=true
    unless has_access?(user)
      record = classroom_records.find_by(user: user)
      if record.present?
        record.update_attributes(role: role, active: active)
      else
        classroom_records.create!(user: user, role: role, active: active)
      end
    end
  end
end
