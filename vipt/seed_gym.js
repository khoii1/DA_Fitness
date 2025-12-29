const axios = require("axios");

const BASE = process.env.BASE_URL || "http://192.168.1.8:3000/api";
const EMAIL = process.env.EMAIL;
const PASSWORD = process.env.PASSWORD;

if (!EMAIL || !PASSWORD) {
  console.error("Please set EMAIL and PASSWORD env vars");
  process.exit(1);
}

async function login() {
  const r = await axios.post(`${BASE}/auth/login`, {
    email: EMAIL,
    password: PASSWORD,
  });
  return r.data.data.token;
}

const meals = [
  {
    name: "Grilled Chicken Breast",
    estimatedCalories: 220,
    asset: "",
    cookTime: 20,
  },
  {
    name: "Brown Rice (1 cup)",
    estimatedCalories: 215,
    asset: "",
    cookTime: 30,
  },
  { name: "Steamed Broccoli", estimatedCalories: 55, asset: "", cookTime: 8 },
  {
    name: "Oatmeal with Banana",
    estimatedCalories: 320,
    asset: "",
    cookTime: 10,
  },
  {
    name: "Greek Yogurt with Honey",
    estimatedCalories: 180,
    asset: "",
    cookTime: 5,
  },
  { name: "Tuna Salad", estimatedCalories: 250, asset: "", cookTime: 10 },
  { name: "Quinoa Salad", estimatedCalories: 300, asset: "", cookTime: 20 },
  { name: "Baked Salmon", estimatedCalories: 350, asset: "", cookTime: 25 },
  {
    name: "Sweet Potato (baked)",
    estimatedCalories: 180,
    asset: "",
    cookTime: 40,
  },
  { name: "Almonds (30g)", estimatedCalories: 170, asset: "", cookTime: 0 },
  {
    name: "Protein Shake (whey)",
    estimatedCalories: 200,
    asset: "",
    cookTime: 5,
  },
  {
    name: "Egg White Omelette",
    estimatedCalories: 150,
    asset: "",
    cookTime: 10,
  },
  {
    name: "Turkey Sandwich (whole grain)",
    estimatedCalories: 330,
    asset: "",
    cookTime: 10,
  },
  { name: "Avocado Toast", estimatedCalories: 260, asset: "", cookTime: 8 },
  { name: "Cottage Cheese", estimatedCalories: 110, asset: "", cookTime: 2 },
  {
    name: "Grilled Steak (lean)",
    estimatedCalories: 400,
    asset: "",
    cookTime: 25,
  },
  {
    name: "Mixed Vegetable Stir Fry",
    estimatedCalories: 220,
    asset: "",
    cookTime: 15,
  },
  { name: "Pancakes (2)", estimatedCalories: 350, asset: "", cookTime: 15 },
  { name: "Chia Seed Pudding", estimatedCalories: 240, asset: "", cookTime: 5 },
  {
    name: "Couscous with Veggies",
    estimatedCalories: 280,
    asset: "",
    cookTime: 15,
  },
  { name: "Grilled Shrimp", estimatedCalories: 180, asset: "", cookTime: 10 },
  {
    name: "Apple with Peanut Butter",
    estimatedCalories: 190,
    asset: "",
    cookTime: 2,
  },
  { name: "Vegetable Soup", estimatedCalories: 150, asset: "", cookTime: 20 },
  {
    name: "Beef Chili (lean)",
    estimatedCalories: 360,
    asset: "",
    cookTime: 40,
  },
  { name: "Protein Pancake", estimatedCalories: 280, asset: "", cookTime: 10 },
  { name: "Tofu Scramble", estimatedCalories: 200, asset: "", cookTime: 12 },
  {
    name: "Salad with Olive Oil",
    estimatedCalories: 210,
    asset: "",
    cookTime: 8,
  },
  {
    name: "Rice Noodles with Veg",
    estimatedCalories: 300,
    asset: "",
    cookTime: 12,
  },
  { name: "Banana (raw)", estimatedCalories: 105, asset: "", cookTime: 0 },
  {
    name: "Canned Sardines on Toast",
    estimatedCalories: 230,
    asset: "",
    cookTime: 3,
  },
];

const workouts = [
  { name: "Push-ups", metValue: 8 },
  { name: "Pull-ups", metValue: 8 },
  { name: "Squats", metValue: 7 },
  { name: "Deadlifts", metValue: 6.5 },
  { name: "Bench Press", metValue: 6 },
  { name: "Overhead Press", metValue: 6 },
  { name: "Bent-over Row", metValue: 6.5 },
  { name: "Lunges", metValue: 6 },
  { name: "Plank", metValue: 4 },
  { name: "Jumping Jacks", metValue: 8 },
  { name: "Burpees", metValue: 10 },
  { name: "Mountain Climbers", metValue: 9 },
  { name: "Bicep Curls", metValue: 4.5 },
  { name: "Tricep Dips", metValue: 4.5 },
  { name: "Kettlebell Swing", metValue: 9 },
  { name: "Rowing (machine)", metValue: 8 },
  { name: "Cycling (stationary)", metValue: 7.5 },
  { name: "Treadmill Run", metValue: 9.5 },
  { name: "Stair Climber", metValue: 8.5 },
  { name: "Box Jumps", metValue: 9 },
  { name: "Leg Press", metValue: 5.5 },
  { name: "Calf Raises", metValue: 3.5 },
  { name: "Lat Pulldown", metValue: 5.5 },
  { name: "Shoulder Fly", metValue: 4.5 },
  { name: "Russian Twist", metValue: 4 },
  { name: "Hip Thrust", metValue: 5.5 },
  { name: "Glute Bridge", metValue: 4 },
  { name: "Step-ups", metValue: 6 },
  { name: "Battle Ropes", metValue: 12 },
];

async function run() {
  const token = await login();
  const headers = { Authorization: `Bearer ${token}` };

  for (let i = 0; i < meals.length; i++) {
    const body = {
      name: meals[i].name,
      asset: meals[i].asset,
      cookTime: meals[i].cookTime,
      estimatedCalories: meals[i].estimatedCalories,
      ingreIDToAmount: {},
    };
    try {
      await axios.post(`${BASE}/meals`, body, { headers });
      console.log("created meal", meals[i].name);
    } catch (e) {
      console.error("meal create failed", meals[i].name, e.message || e);
    }
  }

  for (let i = 0; i < workouts.length; i++) {
    const body = {
      name: workouts[i].name,
      thumbnail: "",
      metValue: workouts[i].metValue,
      description: "Seeded workout",
    };
    try {
      await axios.post(`${BASE}/workouts`, body, { headers });
      console.log("created workout", workouts[i].name);
    } catch (e) {
      console.error("workout create failed", workouts[i].name, e.message || e);
    }
  }

  console.log("Seeding finished");
}

run().catch((err) => {
  console.error("Seeder error", err.message || err);
  process.exit(1);
});

