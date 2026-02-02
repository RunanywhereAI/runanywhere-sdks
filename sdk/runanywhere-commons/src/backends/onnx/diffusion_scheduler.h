/**
 * @file diffusion_scheduler.h
 * @brief Diffusion Schedulers for Stable Diffusion
 *
 * Implements various noise schedulers used in the diffusion process:
 * - DPM++ 2M Karras (recommended)
 * - DDIM
 * - Euler / Euler Ancestral
 *
 * Reference: Hugging Face Diffusers and k-diffusion implementations
 */

#ifndef RUNANYWHERE_DIFFUSION_SCHEDULER_H
#define RUNANYWHERE_DIFFUSION_SCHEDULER_H

#include <cmath>
#include <cstdint>
#include <memory>
#include <random>
#include <string>
#include <vector>

namespace runanywhere {
namespace diffusion {

// =============================================================================
// SCHEDULER TYPES
// =============================================================================

enum class SchedulerType {
    DPM_PP_2M_KARRAS,  // DPM++ 2M with Karras sigmas (recommended)
    DPM_PP_2M,         // DPM++ 2M standard
    DDIM,              // Denoising Diffusion Implicit Models
    EULER,             // Euler method
    EULER_ANCESTRAL,   // Euler Ancestral (adds noise at each step)
    PNDM,              // Pseudo Numerical methods for Diffusion Models
    LMS,               // Linear Multi-Step
};

// =============================================================================
// SCHEDULER CONFIG
// =============================================================================

struct SchedulerConfig {
    int num_train_timesteps = 1000;
    float beta_start = 0.00085f;
    float beta_end = 0.012f;
    std::string beta_schedule = "scaled_linear";  // "linear", "scaled_linear", "squaredcos_cap_v2"
    bool use_karras_sigmas = true;
    float prediction_type = 0;  // 0 = epsilon, 1 = v_prediction
    bool clip_sample = false;
    float clip_sample_range = 1.0f;
    bool thresholding = false;
    float sample_max_value = 1.0f;
};

// =============================================================================
// BASE SCHEDULER
// =============================================================================

/**
 * @brief Base class for all diffusion schedulers
 */
class Scheduler {
   public:
    virtual ~Scheduler() = default;

    /**
     * @brief Create a scheduler of the specified type
     */
    static std::unique_ptr<Scheduler> create(SchedulerType type, const SchedulerConfig& config = {});

    /**
     * @brief Set the number of inference steps
     * @param num_inference_steps Number of denoising steps
     */
    virtual void set_timesteps(int num_inference_steps) = 0;

    /**
     * @brief Get the timesteps for the current schedule
     */
    virtual const std::vector<float>& get_timesteps() const = 0;

    /**
     * @brief Get the initial noise sigma
     */
    virtual float get_init_noise_sigma() const = 0;

    /**
     * @brief Scale the model input (some schedulers need this)
     * @param sample Current latent sample
     * @param timestep Current timestep
     * @return Scaled sample
     */
    virtual std::vector<float> scale_model_input(const std::vector<float>& sample, 
                                                  float timestep) const = 0;

    /**
     * @brief Perform one denoising step
     * @param model_output Noise prediction from UNet
     * @param timestep Current timestep
     * @param sample Current latent sample
     * @param generator Random number generator (for ancestral sampling)
     * @return Updated latent sample
     */
    virtual std::vector<float> step(const std::vector<float>& model_output,
                                    float timestep,
                                    const std::vector<float>& sample,
                                    std::mt19937* generator = nullptr) = 0;

    /**
     * @brief Get current step index
     */
    int get_step_index() const { return step_index_; }

    /**
     * @brief Reset scheduler state for new generation
     */
    virtual void reset() { step_index_ = 0; }

   protected:
    SchedulerConfig config_;
    std::vector<float> timesteps_;
    std::vector<float> alphas_cumprod_;
    std::vector<float> sigmas_;
    int step_index_ = 0;

    // Helper functions
    void compute_alphas();
    float get_alpha_prod(float t) const;
    float get_sigma(float t) const;
};

// =============================================================================
// DPM++ 2M SCHEDULER
// =============================================================================

/**
 * @brief DPM-Solver++ 2nd order multi-step scheduler
 *
 * Implements the DPM-Solver++2M algorithm from:
 * "DPM-Solver++: Fast Solver for Guided Sampling of Diffusion Probabilistic Models"
 */
class DPMPPScheduler : public Scheduler {
   public:
    explicit DPMPPScheduler(const SchedulerConfig& config = {});

    void set_timesteps(int num_inference_steps) override;
    const std::vector<float>& get_timesteps() const override { return timesteps_; }
    float get_init_noise_sigma() const override;
    std::vector<float> scale_model_input(const std::vector<float>& sample, 
                                          float timestep) const override;
    std::vector<float> step(const std::vector<float>& model_output,
                           float timestep,
                           const std::vector<float>& sample,
                           std::mt19937* generator = nullptr) override;
    void reset() override;

   private:
    std::vector<float> compute_karras_sigmas(int num_inference_steps);
    std::vector<std::vector<float>> model_outputs_;  // Store previous model outputs for multi-step
    int num_inference_steps_ = 0;
};

// =============================================================================
// DDIM SCHEDULER
// =============================================================================

/**
 * @brief Denoising Diffusion Implicit Models scheduler
 *
 * Implements DDIM from:
 * "Denoising Diffusion Implicit Models" (Song et al., 2020)
 */
class DDIMScheduler : public Scheduler {
   public:
    explicit DDIMScheduler(const SchedulerConfig& config = {});

    void set_timesteps(int num_inference_steps) override;
    const std::vector<float>& get_timesteps() const override { return timesteps_; }
    float get_init_noise_sigma() const override { return 1.0f; }
    std::vector<float> scale_model_input(const std::vector<float>& sample, 
                                          float timestep) const override;
    std::vector<float> step(const std::vector<float>& model_output,
                           float timestep,
                           const std::vector<float>& sample,
                           std::mt19937* generator = nullptr) override;

   private:
    float eta_ = 0.0f;  // DDIM eta parameter (0 = deterministic)
};

// =============================================================================
// EULER SCHEDULER
// =============================================================================

/**
 * @brief Euler method scheduler
 *
 * Simple first-order ODE solver for diffusion sampling.
 */
class EulerScheduler : public Scheduler {
   public:
    explicit EulerScheduler(const SchedulerConfig& config = {}, bool ancestral = false);

    void set_timesteps(int num_inference_steps) override;
    const std::vector<float>& get_timesteps() const override { return timesteps_; }
    float get_init_noise_sigma() const override;
    std::vector<float> scale_model_input(const std::vector<float>& sample, 
                                          float timestep) const override;
    std::vector<float> step(const std::vector<float>& model_output,
                           float timestep,
                           const std::vector<float>& sample,
                           std::mt19937* generator = nullptr) override;

   private:
    bool ancestral_;  // If true, use Euler Ancestral (adds noise)
};

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * @brief Generate random latent tensor
 * @param batch_size Batch size (typically 1)
 * @param channels Number of latent channels (typically 4)
 * @param height Height of latent (image_height / 8)
 * @param width Width of latent (image_width / 8)
 * @param seed Random seed (-1 for random)
 * @return Random latent tensor as flat vector
 */
std::vector<float> generate_random_latents(int batch_size, int channels, 
                                           int height, int width, 
                                           int64_t seed = -1);

/**
 * @brief Element-wise vector operations
 */
std::vector<float> vector_add(const std::vector<float>& a, const std::vector<float>& b);
std::vector<float> vector_sub(const std::vector<float>& a, const std::vector<float>& b);
std::vector<float> vector_mul(const std::vector<float>& a, float scalar);
std::vector<float> vector_mul(const std::vector<float>& a, const std::vector<float>& b);

}  // namespace diffusion
}  // namespace runanywhere

#endif  // RUNANYWHERE_DIFFUSION_SCHEDULER_H
