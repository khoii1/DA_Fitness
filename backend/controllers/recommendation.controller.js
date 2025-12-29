import mongoose from "mongoose";
import User from "../models/User.model.js";
import WorkoutPlan from "../models/WorkoutPlan.model.js";
import PlanExerciseCollection from "../models/PlanExerciseCollection.model.js";
import PlanMealCollection from "../models/PlanMealCollection.model.js";
import PlanExercise from "../models/PlanExercise.model.js";
import PlanMeal from "../models/PlanMeal.model.js";
import PlanExerciseCollectionSetting from "../models/PlanExerciseCollectionSetting.model.js";
import Workout from "../models/Workout.model.js";
import Meal from "../models/Meal.model.js";
import recommendationService from "../services/recommendationService.js";

/**
 * @desc    Generate workout and meal plan recommendation
 * @route   POST /api/recommendations/generate-plan
 * @access  Private
 */
export const generatePlan = async (req, res) => {
  try {
    const userId = req.user.id;

    // Get user with all profile data
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    // Validate required fields
    if (!user.currentWeight || !user.goalWeight || !user.currentHeight) {
      return res.status(400).json({
        success: false,
        message:
          "Missing required user information: currentWeight, goalWeight, and currentHeight are required",
      });
    }

    // Generate plan recommendation
    const planData = await recommendationService.generatePlan(user);

    res.status(200).json({
      success: true,
      data: planData,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

/**
 * @desc    Create workout and meal plan from recommendation
 * @route   POST /api/recommendations/create-plan
 * @access  Private
 */
export const createPlan = async (req, res) => {
  try {
    const userId = req.user.id;
    const {
      planLengthInDays,
      dailyGoalCalories,
      dailyIntakeCalories,
      dailyOuttakeCalories,
      recommendedExerciseIDs,
      recommendedMealIDs,
      startDate,
      endDate,
    } = req.body;

    // Validate required fields
    if (
      !planLengthInDays ||
      !dailyGoalCalories ||
      !recommendedExerciseIDs ||
      !recommendedMealIDs
    ) {
      return res.status(400).json({
        success: false,
        message:
          "Missing required fields: planLengthInDays, dailyGoalCalories, recommendedExerciseIDs, recommendedMealIDs",
      });
    }

    // Get user
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    // Delete existing plan if exists
    const existingPlan = await WorkoutPlan.findOne({ userID: userId });
    if (existingPlan) {
      // Get existing planID before deleting
      const existingPlanID = existingPlan.planID || 0;
      // Delete existing collections
      await PlanExerciseCollection.deleteMany({ planID: existingPlanID });
      await PlanMealCollection.deleteMany({ planID: existingPlanID });
      await WorkoutPlan.findByIdAndDelete(existingPlan._id);
    }

    // Generate a unique planID (simple incrementing approach)
    // In production, you might want to use a more robust ID generation
    const lastPlan = await WorkoutPlan.findOne().sort({ planID: -1 }).limit(1);
    let planID = 1;
    if (lastPlan && lastPlan.planID) {
      planID = lastPlan.planID + 1;
    }

    // Create new workout plan
    const workoutPlan = await WorkoutPlan.create({
      userID: userId,
      planID: planID,
      dailyGoalCalories: dailyGoalCalories,
      startDate: startDate ? new Date(startDate) : new Date(),
      endDate: endDate
        ? new Date(endDate)
        : new Date(Date.now() + planLengthInDays * 24 * 60 * 60 * 1000),
    });

    // Gán planID mới cho user (luu vào record user) để client có thể khôi phục nhanh
    try {
      if (workoutPlan && workoutPlan.planID != null) {
        await User.findByIdAndUpdate(userId, {
          currentPlanID: workoutPlan.planID,
        }).catch(() => {});
      }
    } catch (e) {
      // Không làm gián đoạn luồng chính nếu cập nhật user thất bại
      console.warn("Failed to set currentPlanID on user:", e);
    }

    // Create exercise and meal collections for the first 7 days initially (reduced from 60)
    // This significantly reduces the initial creation time and API calls
    const daysToCreate = Math.min(planLengthInDays, 7);
    const createdExerciseCollections = [];
    const createdMealCollections = [];

    // Pre-fetch recommended meals and workouts to avoid repeated queries
    const recommendedMealDocs = await Meal.find({
      _id: {
        $in: recommendedMealIDs.map((id) => new mongoose.Types.ObjectId(id)),
      },
    }).lean();

    // Keep track of previous day's selected meal IDs to avoid consecutive repeats
    let prevMealIds = new Set();
    // Global count per meal id to enforce max occurrences across the plan
    const mealCounts = {};
    const MAX_OCCURRENCE_PER_MEAL = 2; // N = 2 by default
    // Track all meal combinations used to ensure each day has unique 3-meal combination
    const usedMealCombinations = new Set();

    // Prepare bulk operations for better performance
    const exerciseSettingsToCreate = [];
    const exerciseCollectionsToCreate = [];
    const planExercisesToCreate = [];
    const mealCollectionsToCreate = [];
    const planMealsToCreate = [];

    for (let i = 0; i < daysToCreate; i++) {
      const date = new Date();
      date.setDate(date.getDate() + i);
      date.setHours(0, 0, 0, 0);

      // Determine exercises per day (randomly 3-4)
      const exercisesPerDay = 3 + Math.floor(Math.random() * 2); // 3 or 4
      const exercisesForDay = selectRandomExercises(
        recommendedExerciseIDs,
        exercisesPerDay
      );
      console.log(
        `🔥 Day ${i + 1} creating ${
          exercisesForDay.length
        } exercises (target: ${exercisesPerDay})`
      );

      // Prepare exercise setting for bulk creation
      const exerciseSettingId = new mongoose.Types.ObjectId();
      exerciseSettingsToCreate.push({
        _id: exerciseSettingId,
        round: 3,
        numOfWorkoutPerRound: exercisesPerDay, // Match actual exercises count
        isStartWithWarmUp: true,
        isShuffle: true,
        exerciseTime: 45,
        transitionTime: 10,
        restTime: 10,
        restFrequency: 10,
      });

      // Prepare exercise collection for bulk creation
      const exerciseCollectionId = new mongoose.Types.ObjectId();
      exerciseCollectionsToCreate.push({
        _id: exerciseCollectionId,
        date: date,
        planID: planID,
        collectionSettingID: exerciseSettingId.toString(),
      });
      const exercisesForThisDay = exercisesForDay.map((exerciseID) => ({
        exerciseID: new mongoose.Types.ObjectId(exerciseID),
        listID: exerciseCollectionId.toString(),
      }));
      planExercisesToCreate.push(...exercisesForThisDay);

      // Prepare meal collection for bulk creation
      const mealCollectionId = new mongoose.Types.ObjectId();
      mealCollectionsToCreate.push({
        _id: mealCollectionId,
        date: date,
        planID: planID,
        mealRatio: 1.0,
      });

      // Select meals for this day
      let mealsCount = 3;

      // Get workout docs for today's exercises to determine intensity
      const workoutDocs = await Workout.find({
        _id: {
          $in: exercisesForDay.map((id) => new mongoose.Types.ObjectId(id)),
        },
      }).lean();

      // Compute average MET for today's exercises
      const avgMET =
        workoutDocs.length > 0
          ? workoutDocs.reduce((s, w) => s + (w.metValue || 5), 0) /
            workoutDocs.length
          : 0;

      // If average MET is high, prefer protein-rich meals
      const preferProtein = avgMET >= 6;

      // Simple selection strategy
      const targetPerMeal = Math.max(
        300,
        Math.round(dailyIntakeCalories / Math.max(1, mealsCount))
      );

      // Rank meals
      const rankedMeals = recommendedMealDocs
        .map((m) => {
          const proteinScore =
            Array.isArray(m.proteinSources) && m.proteinSources.length > 0
              ? 1
              : 0;
          const calorieDiff = Math.abs((m.calories || 500) - targetPerMeal);
          const score =
            (preferProtein ? -proteinScore * 1000 : 0) + calorieDiff;
          return { meal: m, score };
        })
        .sort((a, b) => a.score - b.score)
        .map((r) => r.meal);

      // Select meals with unique 3-meal combination for each day
      let selectedMealsForDay = [];
      let foundUniqueCombination = false;

      // Shuffle meals for randomness
      const shuffledMeals = [...rankedMeals].sort(() => Math.random() - 0.5);

      // Try to find a unique combination by trying different triplets
      for (
        let i = 0;
        i < Math.min(shuffledMeals.length - 2, 20) && !foundUniqueCombination;
        i++
      ) {
        for (
          let j = i + 1;
          j < Math.min(shuffledMeals.length - 1, i + 10) &&
          !foundUniqueCombination;
          j++
        ) {
          for (
            let k = j + 1;
            k < Math.min(shuffledMeals.length, j + 10) &&
            !foundUniqueCombination;
            k++
          ) {
            const candidateMeals = [
              shuffledMeals[i],
              shuffledMeals[j],
              shuffledMeals[k],
            ];
            const mealIds = candidateMeals.map((m) => m._id.toString()).sort();
            const combinationKey = mealIds.join(",");

            if (!usedMealCombinations.has(combinationKey)) {
              selectedMealsForDay = candidateMeals;
              usedMealCombinations.add(combinationKey);
              foundUniqueCombination = true;
            }
          }
        }
      }

      // If still not found unique combination, use fallback: try to find any unused combination
      if (!foundUniqueCombination) {
        // Try a more aggressive search for unused combinations
        let attempts = 0;
        const maxAttempts = 50; // Prevent infinite loops

        while (!foundUniqueCombination && attempts < maxAttempts) {
          // Shuffle and try different combinations
          const tempMeals = [...shuffledMeals].sort(() => Math.random() - 0.5);
          if (tempMeals.length >= mealsCount) {
            const candidateMeals = tempMeals.slice(0, mealsCount);
            const candidateIds = candidateMeals
              .map((m) => m._id.toString())
              .sort();
            const combinationKey = candidateIds.join(",");

            if (!usedMealCombinations.has(combinationKey)) {
              selectedMealsForDay = candidateMeals;
              usedMealCombinations.add(combinationKey);
              foundUniqueCombination = true;
              console.log(
                `✅ Found alternative unique combination for day ${
                  i + 1
                } on attempt ${attempts + 1}`
              );
            }
          }
          attempts++;
        }

        // If still no unique combination found after many attempts, allow reuse but log warning
        if (!foundUniqueCombination) {
          if (shuffledMeals.length >= mealsCount) {
            selectedMealsForDay = shuffledMeals.slice(0, mealsCount);
            const mealIds = selectedMealsForDay
              .map((m) => m._id.toString())
              .sort();
            const combinationKey = mealIds.join(",");
            console.log(
              `⚠️ Warning: Using duplicate combination for day ${
                i + 1
              }: ${combinationKey}`
            );
          } else {
            // Emergency fallback: use all available meals
            selectedMealsForDay = shuffledMeals.slice();
            console.log(
              `⚠️ Warning: Not enough meals available for day ${i + 1} (${
                selectedMealsForDay.length
              }/${mealsCount})`
            );
          }
        }
      }

      const finalSelectedMeals = selectedMealsForDay.slice(0, mealsCount);
      const mealsForThisDay = finalSelectedMeals.map((meal) => ({
        mealID: new mongoose.Types.ObjectId(meal._id),
        listID: mealCollectionId.toString(),
      }));
      planMealsToCreate.push(...mealsForThisDay);

      // Update meal counts for global tracking
      for (const meal of finalSelectedMeals) {
        const idStr = meal._id.toString();
        mealCounts[idStr] = (mealCounts[idStr] || 0) + 1;
      }

      // Log the selected combination for debugging
      const mealIds = finalSelectedMeals.map((m) => m._id.toString());
      console.log(
        `🔍 Day ${i + 1} selected meals: ${mealIds.length} ids=${mealIds.join(
          ","
        )} (unique combination: ${foundUniqueCombination ? "YES" : "NO"})`
      );

      createdExerciseCollections.push(exerciseCollectionId);
      createdMealCollections.push(mealCollectionId);

      // Update prevMealIds for next day
      prevMealIds = new Set(finalSelectedMeals.map((m) => m._id.toString()));
    }

    // Execute bulk operations for better performance
    await PlanExerciseCollectionSetting.insertMany(exerciseSettingsToCreate);
    await PlanExerciseCollection.insertMany(exerciseCollectionsToCreate);
    await PlanExercise.insertMany(planExercisesToCreate);
    await PlanMealCollection.insertMany(mealCollectionsToCreate);
    await PlanMeal.insertMany(planMealsToCreate);

    res.status(201).json({
      success: true,
      data: {
        plan: workoutPlan,
        planID: workoutPlan.planID,
        createdDays: daysToCreate,
        exerciseCollectionsCreated: createdExerciseCollections.length,
        mealCollectionsCreated: createdMealCollections.length,
        message: `Plan created successfully with ${daysToCreate} days of exercises and meals. Additional days will be created as needed.`,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

/**
 * @desc    Get plan recommendation preview (without creating plan)
 * @route   GET /api/recommendations/preview
 * @access  Private
 */
export const getPlanPreview = async (req, res) => {
  try {
    const userId = req.user.id;

    // Sử dụng lean() để query nhanh hơn
    const user = await User.findById(userId).lean();
    if (!user) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    if (!user.currentWeight || !user.goalWeight || !user.currentHeight) {
      return res.status(400).json({
        success: false,
        message:
          "Missing required user information. Please complete your profile setup.",
      });
    }

    const planData = await recommendationService.generatePlan(user);

    // Ensure we have arrays
    const exerciseIDs = Array.isArray(planData.recommendedExerciseIDs)
      ? planData.recommendedExerciseIDs
      : [];
    const mealIDs = Array.isArray(planData.recommendedMealIDs)
      ? planData.recommendedMealIDs
      : [];

    // Convert to mongoose ObjectId if needed
    const exerciseObjectIds = exerciseIDs
      .map((id) => {
        if (mongoose.Types.ObjectId.isValid(id)) {
          return typeof id === "string" ? new mongoose.Types.ObjectId(id) : id;
        }
        return null;
      })
      .filter((id) => id !== null);

    const mealObjectIds = mealIDs
      .map((id) => {
        if (mongoose.Types.ObjectId.isValid(id)) {
          return typeof id === "string" ? new mongoose.Types.ObjectId(id) : id;
        }
        return null;
      })
      .filter((id) => id !== null);

    // Get exercise and meal details song song với lean() để nhanh hơn
    const [exercises, meals] = await Promise.all([
      exerciseObjectIds.length > 0
        ? Workout.find({ _id: { $in: exerciseObjectIds } }).lean()
        : Promise.resolve([]),
      mealObjectIds.length > 0
        ? Meal.find({ _id: { $in: mealObjectIds } }).lean()
        : Promise.resolve([]),
    ]);

    // Convert dates to ISO strings for JSON response
    const responseData = {
      ...planData,
      startDate:
        planData.startDate instanceof Date
          ? planData.startDate.toISOString()
          : planData.startDate,
      endDate:
        planData.endDate instanceof Date
          ? planData.endDate.toISOString()
          : planData.endDate,
      recommendedExerciseIDs: exerciseIDs.map((id) => id.toString()),
      recommendedMealIDs: mealIDs.map((id) => id.toString()),
      exercises,
      meals,
    };

    res.status(200).json({
      success: true,
      data: responseData,
    });
  } catch (error) {
    console.error("Error in getPlanPreview:", error);
    res.status(500).json({
      success: false,
      message: error.message || "Internal server error",
      stack: process.env.NODE_ENV === "development" ? error.stack : undefined,
    });
  }
};

/**
 * @desc    Get the latest plan for the authenticated user
 * @route   GET /api/recommendations/my-plan
 * @access  Private
 */
export const getMyPlan = async (req, res) => {
  try {
    const userId = req.user.id;
    const plan = await WorkoutPlan.findOne({ userID: userId })
      .sort({ planID: -1 })
      .limit(1)
      .lean();
    if (!plan) {
      return res
        .status(404)
        .json({ success: false, message: "Plan not found" });
    }
    res.status(200).json({ success: true, data: plan });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message || "Internal server error",
    });
  }
};

/**
 * @desc    Extend an existing plan by adding more days
 * @route   POST /api/recommendations/extend-plan
 * @access  Private
 */
export const extendPlan = async (req, res) => {
  try {
    const userId = req.user.id;
    const {
      planID,
      daysToAdd = 7,
      recommendedExerciseIDs = [],
      recommendedMealIDs = [],
    } = req.body;

    if (!planID || daysToAdd <= 0) {
      return res.status(400).json({
        success: false,
        message: "Missing or invalid fields: planID and daysToAdd are required",
      });
    }

    // Find the plan and ensure it belongs to the user
    // planID param may be numeric planID or a Mongo _id string. Try robust lookup.
    let workoutPlan = null;
    // Try treating planID as Mongo ObjectId if valid
    try {
      if (mongoose.Types.ObjectId.isValid(planID)) {
        workoutPlan = await WorkoutPlan.findOne({
          _id: planID,
          userID: userId,
        }).lean();
      }
    } catch (err) {
      // ignore
    }

    // If not found, try numeric planID field
    if (!workoutPlan) {
      const numericPlanID = Number(planID);
      if (!isNaN(numericPlanID)) {
        workoutPlan = await WorkoutPlan.findOne({
          planID: numericPlanID,
          userID: userId,
        }).lean();
      }
    }

    // Fallback: try latest plan by userID
    if (!workoutPlan) {
      workoutPlan = await WorkoutPlan.findOne({ userID: userId })
        .sort({ planID: -1 })
        .limit(1)
        .lean();
    }

    if (!workoutPlan) {
      return res
        .status(404)
        .json({ success: false, message: "Plan not found" });
    }

    // Resolve canonical numeric planID from found workoutPlan
    const resolvedPlanID = workoutPlan.planID || (workoutPlan._id ? 0 : 0);

    // Determine last date already created for this plan
    const lastMealCollection = await PlanMealCollection.findOne({
      planID: resolvedPlanID,
    })
      .sort({ date: -1 })
      .limit(1)
      .lean();
    const lastExerciseCollection = await PlanExerciseCollection.findOne({
      planID: resolvedPlanID,
    })
      .sort({ date: -1 })
      .limit(1)
      .lean();

    let startDate = null;
    if (lastMealCollection && lastExerciseCollection) {
      // pick the later date to continue from
      startDate = new Date(
        Math.max(
          new Date(lastMealCollection.date).getTime(),
          new Date(lastExerciseCollection.date).getTime()
        )
      );
    } else if (lastMealCollection) {
      startDate = new Date(lastMealCollection.date);
    } else if (lastExerciseCollection) {
      startDate = new Date(lastExerciseCollection.date);
    } else {
      startDate = workoutPlan.startDate
        ? new Date(workoutPlan.startDate)
        : new Date();
      // move one day back so first added day is plan.startDate
      startDate.setDate(startDate.getDate() - 1);
    }

    // Clamp daysToAdd to a safe maximum
    const MAX_DAYS_TO_ADD = 30;
    const safeDaysToAdd = Math.min(
      Math.max(parseInt(daysToAdd, 10) || 0, 1),
      MAX_DAYS_TO_ADD
    );
    // Try to acquire a per-plan lock with expiration to avoid concurrent extends (stale-lock safe)
    const LOCK_TIMEOUT_MS = 30 * 1000; // 30 seconds
    const now = new Date();
    const lockExpiresAt = new Date(now.getTime() + LOCK_TIMEOUT_MS);

    const lockQuery = {
      planID: resolvedPlanID,
      userID: userId,
      $or: [
        { isExtending: { $ne: true } },
        { isExtendingExpiresAt: { $lt: now } },
        { isExtendingExpiresAt: { $exists: false } },
      ],
    };

    const lockResult = await WorkoutPlan.findOneAndUpdate(
      lockQuery,
      { $set: { isExtending: true, isExtendingExpiresAt: lockExpiresAt } },
      { returnDocument: "after" }
    );
    if (!lockResult) {
      return res.status(409).json({
        success: false,
        message: "Plan is being extended by another request. Try again later.",
      });
    }

    // Pre-fetch recommended meals if provided
    const recommendedMealDocs =
      recommendedMealIDs && recommendedMealIDs.length > 0
        ? await Meal.find({
            _id: {
              $in: recommendedMealIDs.map(
                (id) => new mongoose.Types.ObjectId(id)
              ),
            },
          }).lean()
        : [];

    // Initialize global meal counts from existing plan (to enforce max occurrences)
    const existingCollections = await PlanMealCollection.find({
      planID: resolvedPlanID,
    })
      .select("_id")
      .lean();
    const collectionIds = existingCollections.map((c) => c._id.toString());
    const existingPlanMeals =
      collectionIds.length > 0
        ? await PlanMeal.find({ listID: { $in: collectionIds } }).lean()
        : [];
    const mealCounts = {};
    // Track all meal combinations used in existing plan
    const usedMealCombinations = new Set();

    // Build existing combinations from current plan
    const existingMealGroups = {};
    for (const pm of existingPlanMeals) {
      const collectionId = pm.listID?.toString();
      const mealId =
        pm.mealID && pm.mealID.toString
          ? pm.mealID.toString()
          : (pm.mealID || "").toString();
      if (collectionId && mealId) {
        if (!existingMealGroups[collectionId]) {
          existingMealGroups[collectionId] = [];
        }
        existingMealGroups[collectionId].push(mealId);
        mealCounts[mealId] = (mealCounts[mealId] || 0) + 1;
      }
    }

    // Create combination keys from existing groups
    for (const mealIds of Object.values(existingMealGroups)) {
      if (mealIds.length >= 3) {
        const sortedIds = [...mealIds].sort();
        const combinationKey = sortedIds.join(",");
        usedMealCombinations.add(combinationKey);
      }
    }

    const MAX_OCCURRENCE_PER_MEAL = 2; // default limit

    // Bulk create arrays
    const exerciseSettingsToCreate = [];
    const exerciseCollectionsToCreate = [];
    const planExercisesToCreate = [];
    const mealCollectionsToCreate = [];
    const planMealsToCreate = [];

    let prevMealIds = new Set();

    // Determine exercises per day for extension (randomly 3-4)
    const exercisesPerDayExtend = 3 + Math.floor(Math.random() * 2); // 3 or 4

    for (let i = 1; i <= safeDaysToAdd; i++) {
      const date = new Date(startDate);
      date.setDate(date.getDate() + i);
      date.setHours(0, 0, 0, 0);

      const exerciseSettingId = new mongoose.Types.ObjectId();
      exerciseSettingsToCreate.push({
        _id: exerciseSettingId,
        round: 3,
        numOfWorkoutPerRound: exercisesForDay.length || 3, // Match actual exercises count
        isStartWithWarmUp: true,
        isShuffle: true,
        exerciseTime: 45,
        transitionTime: 10,
        restTime: 10,
        restFrequency: 10,
      });

      const exerciseCollectionId = new mongoose.Types.ObjectId();
      exerciseCollectionsToCreate.push({
        _id: exerciseCollectionId,
        date: date,
        planID: resolvedPlanID,
        collectionSettingID: exerciseSettingId.toString(),
      });
      const exercisesForDay =
        Array.isArray(recommendedExerciseIDs) &&
        recommendedExerciseIDs.length > 0
          ? selectRandomExercises(recommendedExerciseIDs, exercisesPerDayExtend)
          : [];

      const exercisesForThisDay = exercisesForDay.map((exerciseID) => ({
        exerciseID: new mongoose.Types.ObjectId(exerciseID),
        listID: exerciseCollectionId.toString(),
      }));
      planExercisesToCreate.push(...exercisesForThisDay);

      const mealCollectionId = new mongoose.Types.ObjectId();
      mealCollectionsToCreate.push({
        _id: mealCollectionId,
        date: date,
        planID: resolvedPlanID,
        mealRatio: 1.0,
      });

      // meals selection
      let mealsCount = 3;
      const workoutDocs =
        exercisesForDay.length > 0
          ? await Workout.find({
              _id: {
                $in: exercisesForDay.map(
                  (id) => new mongoose.Types.ObjectId(id)
                ),
              },
            }).lean()
          : [];

      const avgMET =
        workoutDocs.length > 0
          ? workoutDocs.reduce((s, w) => s + (w.metValue || 5), 0) /
            workoutDocs.length
          : 0;

      const preferProtein = avgMET >= 6;
      const targetPerMeal = Math.max(
        300,
        Math.round(
          (workoutPlan.dailyIntakeCalories || 0) / Math.max(1, mealsCount)
        )
      );

      const rankedMeals =
        recommendedMealDocs.length > 0
          ? recommendedMealDocs
              .map((m) => {
                const proteinScore =
                  Array.isArray(m.proteinSources) && m.proteinSources.length > 0
                    ? 1
                    : 0;
                const calorieDiff = Math.abs(
                  (m.calories || 500) - targetPerMeal
                );
                const score =
                  (preferProtein ? -proteinScore * 1000 : 0) + calorieDiff;
                return { meal: m, score };
              })
              .sort((a, b) => a.score - b.score)
              .map((r) => r.meal)
          : [];

      // Select meals with unique 3-meal combination for each day
      let selectedMealsForDay = [];
      let foundUniqueCombination = false;

      // Shuffle meals for randomness
      const shuffledMeals = [...rankedMeals].sort(() => Math.random() - 0.5);

      // Try to find a unique combination by trying different triplets
      for (
        let i = 0;
        i < Math.min(shuffledMeals.length - 2, 20) && !foundUniqueCombination;
        i++
      ) {
        for (
          let j = i + 1;
          j < Math.min(shuffledMeals.length - 1, i + 10) &&
          !foundUniqueCombination;
          j++
        ) {
          for (
            let k = j + 1;
            k < Math.min(shuffledMeals.length, j + 10) &&
            !foundUniqueCombination;
            k++
          ) {
            const candidateMeals = [
              shuffledMeals[i],
              shuffledMeals[j],
              shuffledMeals[k],
            ];
            const mealIds = candidateMeals.map((m) => m._id.toString()).sort();
            const combinationKey = mealIds.join(",");

            if (!usedMealCombinations.has(combinationKey)) {
              selectedMealsForDay = candidateMeals;
              usedMealCombinations.add(combinationKey);
              foundUniqueCombination = true;
            }
          }
        }
      }

      // If still not found unique combination, use fallback: try to find any unused combination
      if (!foundUniqueCombination) {
        // Try a more aggressive search for unused combinations
        let attempts = 0;
        const maxAttempts = 50; // Prevent infinite loops

        while (!foundUniqueCombination && attempts < maxAttempts) {
          // Shuffle and try different combinations
          const tempMeals = [...shuffledMeals].sort(() => Math.random() - 0.5);
          if (tempMeals.length >= mealsCount) {
            const candidateMeals = tempMeals.slice(0, mealsCount);
            const candidateIds = candidateMeals
              .map((m) => m._id.toString())
              .sort();
            const combinationKey = candidateIds.join(",");

            if (!usedMealCombinations.has(combinationKey)) {
              selectedMealsForDay = candidateMeals;
              usedMealCombinations.add(combinationKey);
              foundUniqueCombination = true;
              console.log(
                `✅ Found alternative unique combination for extend day ${
                  i + 1
                } on attempt ${attempts + 1}`
              );
            }
          }
          attempts++;
        }

        // If still no unique combination found after many attempts, allow reuse but log warning
        if (!foundUniqueCombination) {
          if (shuffledMeals.length >= mealsCount) {
            selectedMealsForDay = shuffledMeals.slice(0, mealsCount);
            const mealIds = selectedMealsForDay
              .map((m) => m._id.toString())
              .sort();
            const combinationKey = mealIds.join(",");
            console.log(
              `⚠️ Warning: Using duplicate combination for extend day ${
                i + 1
              }: ${combinationKey}`
            );
          } else {
            // Emergency fallback: use all available meals
            selectedMealsForDay = shuffledMeals.slice();
            console.log(
              `⚠️ Warning: Not enough meals available for extend day ${
                i + 1
              } (${selectedMealsForDay.length}/${mealsCount})`
            );
          }
        }
      }

      // Update meal counts for selected meals
      for (const meal of selectedMealsForDay.slice(0, mealsCount)) {
        const idStr = meal._id.toString();
        mealCounts[idStr] = (mealCounts[idStr] || 0) + 1;
      }

      const finalSelectedMeals = selectedMealsForDay.slice(0, mealsCount);
      const mealsForThisDay = finalSelectedMeals.map((meal) => ({
        mealID: new mongoose.Types.ObjectId(meal._id),
        listID: mealCollectionId.toString(),
      }));
      planMealsToCreate.push(...mealsForThisDay);

      // Log the selected combination for debugging
      const mealIds = finalSelectedMeals.map((m) => m._id.toString());
      console.log(
        `🔍 Extend Day ${i + 1} selected meals: ${
          mealIds.length
        } ids=${mealIds.join(",")} (unique combination: ${
          foundUniqueCombination ? "YES" : "NO"
        })`
      );

      // Update prevMealIds for next day
      prevMealIds = new Set(finalSelectedMeals.map((m) => m._id.toString()));
    }

    // Execute bulk writes with ordered:false so duplicate-key won't abort the whole batch
    try {
      if (exerciseSettingsToCreate.length)
        await PlanExerciseCollectionSetting.insertMany(
          exerciseSettingsToCreate,
          { ordered: false }
        );
      if (exerciseCollectionsToCreate.length)
        await PlanExerciseCollection.insertMany(exerciseCollectionsToCreate, {
          ordered: false,
        });
      if (planExercisesToCreate.length)
        await PlanExercise.insertMany(planExercisesToCreate, {
          ordered: false,
        });
      if (mealCollectionsToCreate.length)
        await PlanMealCollection.insertMany(mealCollectionsToCreate, {
          ordered: false,
        });
      if (planMealsToCreate.length)
        await PlanMeal.insertMany(planMealsToCreate, { ordered: false });
    } catch (bulkError) {
      // Ignore duplicate key errors from concurrent inserts; log others
      const isDupKey = bulkError && bulkError.code && bulkError.code === 11000;
      if (!isDupKey) {
        console.error("Bulk insert error in extendPlan:", bulkError);
      }
    } finally {
      // release lock (clear flag and expiry)
      await WorkoutPlan.updateOne(
        { planID: resolvedPlanID, userID: userId },
        { $set: { isExtending: false }, $unset: { isExtendingExpiresAt: "" } }
      ).catch(() => {});
    }

    res.status(201).json({
      success: true,
      data: {
        addedDays: safeDaysToAdd,
        message: `Added ${safeDaysToAdd} days to plan ${resolvedPlanID}`,
      },
    });
  } catch (error) {
    console.error("Error in extendPlan:", error);
    res.status(500).json({
      success: false,
      message: error.message || "Internal server error",
    });
  }
};

// Helper functions
function selectRandomExercises(exerciseIDs, count) {
  const shuffled = [...exerciseIDs].sort(() => Math.random() - 0.5);
  return shuffled.slice(0, Math.min(count, exerciseIDs.length));
}

function selectRandomMeals(mealIDs, count) {
  const shuffled = [...mealIDs].sort(() => Math.random() - 0.5);
  return shuffled.slice(0, Math.min(count, mealIDs.length));
}

// Attach helper functions to exports
export { selectRandomExercises, selectRandomMeals };
