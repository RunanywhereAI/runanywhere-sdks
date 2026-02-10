/**
 * @file diffusion_scheduler.cpp
 * @brief Diffusion Scheduler implementations
 *
 * Implements noise schedulers for Stable Diffusion inference.
 * Based on Hugging Face Diffusers and k-diffusion implementations.
 */

#include "diffusion_scheduler.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <numeric>
#include <stdexcept>

#include "rac/core/rac_logger.h"

namespace runanywhere {
namespace diffusion {

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

std::vector<float> vector_add(const std::vector<float>& a, const std::vector<float>& b) {
    if (a.size() != b.size()) {
        throw std::invalid_argument("Vector sizes must match for addition");
    }
    std::vector<float> result(a.size());
    for (size_t i = 0; i < a.size(); ++i) {
        result[i] = a[i] + b[i];
    }
    return result;
}

std::vector<float> vector_sub(const std::vector<float>& a, const std::vector<float>& b) {
    if (a.size() != b.size()) {
        throw std::invalid_argument("Vector sizes must match for subtraction");
    }
    std::vector<float> result(a.size());
    for (size_t i = 0; i < a.size(); ++i) {
        result[i] = a[i] - b[i];
    }
    return result;
}

std::vector<float> vector_mul(const std::vector<float>& a, float scalar) {
    std::vector<float> result(a.size());
    for (size_t i = 0; i < a.size(); ++i) {
        result[i] = a[i] * scalar;
    }
    return result;
}

std::vector<float> vector_mul(const std::vector<float>& a, const std::vector<float>& b) {
    if (a.size() != b.size()) {
        throw std::invalid_argument("Vector sizes must match for multiplication");
    }
    std::vector<float> result(a.size());
    for (size_t i = 0; i < a.size(); ++i) {
        result[i] = a[i] * b[i];
    }
    return result;
}

std::vector<float> generate_random_latents(int batch_size, int channels, 
                                           int height, int width, 
                                           int64_t seed) {
    size_t total_size = static_cast<size_t>(batch_size) * channels * height * width;
    std::vector<float> latents(total_size);

    // Use provided seed or generate random one
    uint64_t actual_seed;
    if (seed < 0) {
        actual_seed = static_cast<uint64_t>(
            std::chrono::high_resolution_clock::now().time_since_epoch().count());
    } else {
        actual_seed = static_cast<uint64_t>(seed);
    }

    std::mt19937_64 gen(actual_seed);
    std::normal_distribution<float> dist(0.0f, 1.0f);

    for (size_t i = 0; i < total_size; ++i) {
        latents[i] = dist(gen);
    }

    return latents;
}

// =============================================================================
// BASE SCHEDULER
// =============================================================================

std::unique_ptr<Scheduler> Scheduler::create(SchedulerType type, const SchedulerConfig& config) {
    switch (type) {
        case SchedulerType::DPM_PP_2M_KARRAS:
        case SchedulerType::DPM_PP_2M: {
            SchedulerConfig cfg = config;
            cfg.use_karras_sigmas = (type == SchedulerType::DPM_PP_2M_KARRAS);
            return std::make_unique<DPMPPScheduler>(cfg);
        }
        case SchedulerType::DDIM:
            return std::make_unique<DDIMScheduler>(config);
        case SchedulerType::EULER:
            return std::make_unique<EulerScheduler>(config, false);
        case SchedulerType::EULER_ANCESTRAL:
            return std::make_unique<EulerScheduler>(config, true);
        default:
            RAC_LOG_WARNING("Scheduler", "Unknown scheduler type, using DPM++ 2M Karras");
            return std::make_unique<DPMPPScheduler>(config);
    }
}

void Scheduler::compute_alphas() {
    // Compute betas based on schedule type
    std::vector<float> betas(config_.num_train_timesteps);
    
    if (config_.beta_schedule == "linear") {
        for (int i = 0; i < config_.num_train_timesteps; ++i) {
            float t = static_cast<float>(i) / (config_.num_train_timesteps - 1);
            betas[i] = config_.beta_start + t * (config_.beta_end - config_.beta_start);
        }
    } else if (config_.beta_schedule == "scaled_linear") {
        // This is the default for Stable Diffusion
        float sqrt_start = std::sqrt(config_.beta_start);
        float sqrt_end = std::sqrt(config_.beta_end);
        for (int i = 0; i < config_.num_train_timesteps; ++i) {
            float t = static_cast<float>(i) / (config_.num_train_timesteps - 1);
            float sqrt_beta = sqrt_start + t * (sqrt_end - sqrt_start);
            betas[i] = sqrt_beta * sqrt_beta;
        }
    } else if (config_.beta_schedule == "squaredcos_cap_v2") {
        // Cosine schedule
        for (int i = 0; i < config_.num_train_timesteps; ++i) {
            float t = static_cast<float>(i) / config_.num_train_timesteps;
            float alpha_bar = std::cos((t + 0.008f) / 1.008f * M_PI / 2.0f);
            alpha_bar = alpha_bar * alpha_bar;
            
            float t_next = static_cast<float>(i + 1) / config_.num_train_timesteps;
            float alpha_bar_next = std::cos((t_next + 0.008f) / 1.008f * M_PI / 2.0f);
            alpha_bar_next = alpha_bar_next * alpha_bar_next;
            
            betas[i] = std::min(1.0f - alpha_bar_next / alpha_bar, 0.999f);
        }
    }

    // Compute alphas and cumulative products
    std::vector<float> alphas(config_.num_train_timesteps);
    alphas_cumprod_.resize(config_.num_train_timesteps);
    
    float cumprod = 1.0f;
    for (int i = 0; i < config_.num_train_timesteps; ++i) {
        alphas[i] = 1.0f - betas[i];
        cumprod *= alphas[i];
        alphas_cumprod_[i] = cumprod;
    }

    // Compute sigmas from alphas
    sigmas_.resize(config_.num_train_timesteps);
    for (int i = 0; i < config_.num_train_timesteps; ++i) {
        sigmas_[i] = std::sqrt((1.0f - alphas_cumprod_[i]) / alphas_cumprod_[i]);
    }
}

float Scheduler::get_alpha_prod(float t) const {
    // Linear interpolation for non-integer timesteps
    if (t <= 0) return alphas_cumprod_[0];
    if (t >= config_.num_train_timesteps - 1) return alphas_cumprod_.back();
    
    int idx = static_cast<int>(t);
    float frac = t - idx;
    return alphas_cumprod_[idx] * (1.0f - frac) + alphas_cumprod_[idx + 1] * frac;
}

float Scheduler::get_sigma(float t) const {
    if (t <= 0) return sigmas_[0];
    if (t >= config_.num_train_timesteps - 1) return sigmas_.back();
    
    int idx = static_cast<int>(t);
    float frac = t - idx;
    return sigmas_[idx] * (1.0f - frac) + sigmas_[idx + 1] * frac;
}

float Scheduler::sigma_to_t(float sigma) const {
    // Training sigmas (from compute_alphas) are monotonically increasing.
    // Binary search for the interval, then linearly interpolate the timestep.
    if (sigma <= sigmas_[0]) return 0.0f;
    int n = config_.num_train_timesteps;
    if (sigma >= sigmas_[n - 1]) return static_cast<float>(n - 1);

    // Find j such that sigmas_[j] <= sigma < sigmas_[j+1] (ascending order)
    int lo = 0, hi = n - 2;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        if (sigmas_[mid + 1] <= sigma) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    // lo is the largest index where sigmas_[lo] <= sigma
    float frac = (sigma - sigmas_[lo]) / (sigmas_[lo + 1] - sigmas_[lo]);
    return static_cast<float>(lo) + frac;
}

// =============================================================================
// DPM++ 2M SCHEDULER
// =============================================================================

DPMPPScheduler::DPMPPScheduler(const SchedulerConfig& config) {
    config_ = config;
    compute_alphas();
}

std::vector<float> DPMPPScheduler::compute_karras_sigmas(int num_inference_steps) {
    // Karras noise schedule (improved sigma distribution)
    float sigma_min = sigmas_.back();
    float sigma_max = sigmas_[0];
    float rho = 7.0f;  // Karras rho parameter

    std::vector<float> karras_sigmas(num_inference_steps + 1);
    for (int i = 0; i <= num_inference_steps; ++i) {
        float t = static_cast<float>(i) / num_inference_steps;
        float sigma = std::pow(
            std::pow(sigma_max, 1.0f / rho) * (1.0f - t) + std::pow(sigma_min, 1.0f / rho) * t,
            rho);
        karras_sigmas[i] = sigma;
    }
    karras_sigmas.back() = 0.0f;  // Final sigma is 0
    return karras_sigmas;
}

void DPMPPScheduler::set_timesteps(int num_inference_steps) {
    num_inference_steps_ = num_inference_steps;
    model_outputs_.clear();

    // Save the full training sigma schedule (ascending, num_train_timesteps elements)
    // before overwriting sigmas_ with the inference schedule.
    std::vector<float> train_sigmas = sigmas_;

    if (config_.use_karras_sigmas) {
        sigmas_ = compute_karras_sigmas(num_inference_steps);
    } else {
        // Linear timestep spacing
        sigmas_.resize(num_inference_steps + 1);
        for (int i = 0; i <= num_inference_steps; ++i) {
            float t = static_cast<float>(config_.num_train_timesteps - 1) * 
                      (1.0f - static_cast<float>(i) / num_inference_steps);
            // Use training sigmas via get_sigma (which interpolates train_sigmas)
            int idx = static_cast<int>(t);
            float frac = t - idx;
            sigmas_[i] = train_sigmas[idx] * (1.0f - frac) + train_sigmas[std::min(idx + 1, static_cast<int>(train_sigmas.size()) - 1)] * frac;
        }
        sigmas_.back() = 0.0f;
    }

    // Convert inference sigmas to timesteps using the training sigma schedule.
    // sigma_to_t does a binary search through the ascending training sigmas.
    // Temporarily restore training sigmas for the lookup, then set inference sigmas back.
    std::vector<float> inference_sigmas = sigmas_;
    sigmas_ = train_sigmas;

    timesteps_.resize(num_inference_steps);
    for (int i = 0; i < num_inference_steps; ++i) {
        timesteps_[i] = sigma_to_t(inference_sigmas[i]);
    }

    // Restore inference sigmas for use during stepping
    sigmas_ = inference_sigmas;

    step_index_ = 0;
}

float DPMPPScheduler::get_init_noise_sigma() const {
    return sigmas_.empty() ? 1.0f : sigmas_[0];
}

std::vector<float> DPMPPScheduler::scale_model_input(const std::vector<float>& sample, 
                                                      float timestep) const {
    (void)timestep;  // DPM++ doesn't scale input
    return sample;
}

std::vector<float> DPMPPScheduler::step(const std::vector<float>& model_output,
                                        float timestep,
                                        const std::vector<float>& sample,
                                        std::mt19937* generator) {
    (void)timestep;
    (void)generator;

    if (step_index_ >= static_cast<int>(sigmas_.size()) - 1) {
        return sample;
    }

    float sigma = sigmas_[step_index_];
    float sigma_next = sigmas_[step_index_ + 1];

    // Store model output for multi-step
    model_outputs_.push_back(model_output);
    if (model_outputs_.size() > 2) {
        model_outputs_.erase(model_outputs_.begin());
    }

    // Convert to log-space for better numerics
    float lambda = -std::log(sigma);
    float lambda_next = -std::log(std::max(sigma_next, 1e-10f));
    float h = lambda_next - lambda;

    std::vector<float> denoised;
    
    if (model_outputs_.size() == 1 || sigma_next == 0.0f) {
        // First order update
        // x_next = (sigma_next / sigma) * x + (1 - sigma_next / sigma) * denoised
        
        // Predict denoised sample (x0 prediction)
        denoised.resize(sample.size());
        for (size_t i = 0; i < sample.size(); ++i) {
            denoised[i] = sample[i] - sigma * model_output[i];
        }

        if (sigma_next == 0.0f) {
            return denoised;
        }

        std::vector<float> result(sample.size());
        float ratio = sigma_next / sigma;
        for (size_t i = 0; i < sample.size(); ++i) {
            result[i] = ratio * sample[i] + (1.0f - ratio) * denoised[i];
        }
        ++step_index_;
        return result;
    } else {
        // Second order update (DPM++ 2M)
        float lambda_prev = -std::log(sigmas_[step_index_ - 1]);
        float h_last = lambda - lambda_prev;
        float r = h_last / h;

        // Compute denoised predictions
        std::vector<float> d0(sample.size()), d1(sample.size());
        for (size_t i = 0; i < sample.size(); ++i) {
            d0[i] = sample[i] - sigma * model_output[i];
            d1[i] = sample[i] - sigmas_[step_index_ - 1] * model_outputs_[0][i];
        }

        // Multi-step formula
        std::vector<float> result(sample.size());
        float w = sigma_next / sigma;
        for (size_t i = 0; i < sample.size(); ++i) {
            float d_curr = d0[i];
            float d_prime = d0[i] + (d0[i] - d1[i]) * (1.0f / (2.0f * r));
            result[i] = w * sample[i] + (1.0f - w) * d_curr - 
                       (1.0f - w) * h * 0.5f * (d_curr - d_prime) / sigma;
        }
        ++step_index_;
        return result;
    }
}

void DPMPPScheduler::reset() {
    Scheduler::reset();
    model_outputs_.clear();
}

// =============================================================================
// DDIM SCHEDULER
// =============================================================================

DDIMScheduler::DDIMScheduler(const SchedulerConfig& config) {
    config_ = config;
    compute_alphas();
}

void DDIMScheduler::set_timesteps(int num_inference_steps) {
    timesteps_.resize(num_inference_steps);
    
    if (num_inference_steps == 1) {
        // Single-step models (e.g. SDXS): just use the last training timestep
        timesteps_[0] = static_cast<float>(config_.num_train_timesteps - 1);
    } else {
        // Evenly space timesteps
        float step = static_cast<float>(config_.num_train_timesteps - 1) / (num_inference_steps - 1);
        for (int i = 0; i < num_inference_steps; ++i) {
            timesteps_[i] = static_cast<float>(config_.num_train_timesteps - 1) - i * step;
        }
    }
    
    step_index_ = 0;
}

std::vector<float> DDIMScheduler::scale_model_input(const std::vector<float>& sample, 
                                                     float timestep) const {
    (void)timestep;
    return sample;
}

std::vector<float> DDIMScheduler::step(const std::vector<float>& model_output,
                                       float timestep,
                                       const std::vector<float>& sample,
                                       std::mt19937* generator) {
    int t = static_cast<int>(timestep);
    int prev_t = step_index_ + 1 < static_cast<int>(timesteps_.size()) 
                 ? static_cast<int>(timesteps_[step_index_ + 1]) 
                 : 0;

    // Get alpha values
    float alpha_prod_t = get_alpha_prod(static_cast<float>(t));
    float alpha_prod_t_prev = prev_t >= 0 ? get_alpha_prod(static_cast<float>(prev_t)) : 1.0f;

    float beta_prod_t = 1.0f - alpha_prod_t;
    float beta_prod_t_prev = 1.0f - alpha_prod_t_prev;

    // Compute predicted original sample (x0)
    std::vector<float> pred_x0(sample.size());
    float sqrt_alpha = std::sqrt(alpha_prod_t);
    float sqrt_beta = std::sqrt(beta_prod_t);
    
    for (size_t i = 0; i < sample.size(); ++i) {
        pred_x0[i] = (sample[i] - sqrt_beta * model_output[i]) / sqrt_alpha;
    }

    // Clip predicted x0 if configured
    if (config_.clip_sample) {
        for (size_t i = 0; i < pred_x0.size(); ++i) {
            pred_x0[i] = std::clamp(pred_x0[i], -config_.clip_sample_range, 
                                   config_.clip_sample_range);
        }
    }

    // Compute coefficients
    float sqrt_alpha_prev = std::sqrt(alpha_prod_t_prev);
    float sqrt_beta_prev = std::sqrt(beta_prod_t_prev);

    // Compute "direction pointing to x_t"
    std::vector<float> result(sample.size());
    
    // Variance
    float variance = (beta_prod_t_prev / beta_prod_t) * (1.0f - alpha_prod_t / alpha_prod_t_prev);
    float std_dev = eta_ * std::sqrt(variance);

    // Compute x_{t-1}
    for (size_t i = 0; i < sample.size(); ++i) {
        float pred_sample_direction = sqrt_beta_prev * model_output[i];
        result[i] = sqrt_alpha_prev * pred_x0[i] + pred_sample_direction;
    }

    // Add noise if eta > 0
    if (eta_ > 0.0f && generator != nullptr) {
        std::normal_distribution<float> dist(0.0f, 1.0f);
        for (size_t i = 0; i < result.size(); ++i) {
            result[i] += std_dev * dist(*generator);
        }
    }

    ++step_index_;
    return result;
}

// =============================================================================
// EULER SCHEDULER
// =============================================================================

EulerScheduler::EulerScheduler(const SchedulerConfig& config, bool ancestral) 
    : ancestral_(ancestral) {
    config_ = config;
    compute_alphas();
}

void EulerScheduler::set_timesteps(int num_inference_steps) {
    // Compute sigmas for inference
    std::vector<float> inference_sigmas(num_inference_steps + 1);
    
    for (int i = 0; i <= num_inference_steps; ++i) {
        float t = static_cast<float>(config_.num_train_timesteps - 1) * 
                  (1.0f - static_cast<float>(i) / num_inference_steps);
        inference_sigmas[i] = get_sigma(t);
    }
    inference_sigmas.back() = 0.0f;
    
    sigmas_ = inference_sigmas;

    // Store timesteps
    timesteps_.resize(num_inference_steps);
    for (int i = 0; i < num_inference_steps; ++i) {
        timesteps_[i] = sigmas_[i];  // Euler uses sigma as timestep
    }
    
    step_index_ = 0;
}

float EulerScheduler::get_init_noise_sigma() const {
    return sigmas_.empty() ? 1.0f : sigmas_[0];
}

std::vector<float> EulerScheduler::scale_model_input(const std::vector<float>& sample, 
                                                      float timestep) const {
    // Euler scales by sqrt(sigma^2 + 1)
    float sigma = timestep;
    float scale = 1.0f / std::sqrt(sigma * sigma + 1.0f);
    return vector_mul(sample, scale);
}

std::vector<float> EulerScheduler::step(const std::vector<float>& model_output,
                                        float timestep,
                                        const std::vector<float>& sample,
                                        std::mt19937* generator) {
    (void)timestep;
    
    if (step_index_ >= static_cast<int>(sigmas_.size()) - 1) {
        return sample;
    }

    float sigma = sigmas_[step_index_];
    float sigma_next = sigmas_[step_index_ + 1];

    // Convert model output (noise prediction) to derivative
    std::vector<float> derivative(sample.size());
    for (size_t i = 0; i < sample.size(); ++i) {
        derivative[i] = (sample[i] - model_output[i]) / sigma;
    }

    float dt = sigma_next - sigma;
    std::vector<float> result(sample.size());

    if (ancestral_ && generator != nullptr && sigma_next > 0.0f) {
        // Euler Ancestral: add noise at each step
        float sigma_up = std::min(sigma_next, 
            std::sqrt(sigma_next * sigma_next * (sigma * sigma - sigma_next * sigma_next) / 
                     (sigma * sigma)));
        float sigma_down = std::sqrt(sigma_next * sigma_next - sigma_up * sigma_up);
        
        dt = sigma_down - sigma;
        
        std::normal_distribution<float> dist(0.0f, 1.0f);
        for (size_t i = 0; i < sample.size(); ++i) {
            result[i] = sample[i] + derivative[i] * dt + sigma_up * dist(*generator);
        }
    } else {
        // Standard Euler
        for (size_t i = 0; i < sample.size(); ++i) {
            result[i] = sample[i] + derivative[i] * dt;
        }
    }

    ++step_index_;
    return result;
}

}  // namespace diffusion
}  // namespace runanywhere
